//
//  WXYCProxyClientTests.swift
//  Core
//
//  Tests for `WXYCProxyClient`: the shared authed-or-anonymous GET+decode
//  pipeline for api.wxyc.org's proxy endpoints (#761). Uses CoreTesting's
//  `QueuedStubURLProtocol` so both the authed and unauthed paths run without
//  touching the network.
//
//  Declared as an extension of `AuthedDataTests` (`AuthedDataTests.swift`)
//  rather than its own `@Suite`: `QueuedStubURLProtocol`'s handler is shared
//  global mutable state, and that suite's `.serialized` trait is what keeps
//  concurrent tests from racing on it. A separate `@Suite` — even one also
//  marked `.serialized` — runs in parallel with `AuthedDataTests` regardless,
//  since traits only serialize tests *within* a suite. (Confirmed the hard
//  way: an earlier version of this file used its own `@Suite` and, under the
//  full `swift test` run, both suites raced on `QueuedStubURLProtocol` and
//  produced cross-contaminated responses/capture counts. Filtering to just
//  this suite with `--filter` hid the race because nothing else touched the
//  protocol during that run.)
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreTesting
import Foundation
import Testing
@testable import Core

private struct Widget: Decodable, Equatable {
    let name: String
}

extension AuthedDataTests {

    @Test("WXYCProxyClient unauthed: decodes the response and sends no Authorization header")
    func proxyClientUnauthedDecodesAndSendsNoAuthHeader() async throws {
        QueuedStubURLProtocol.setBody(Data(#"{"name":"Juana Molina"}"#.utf8))
        let client = WXYCProxyClient(
            baseURL: URL(string: "https://api.wxyc.org")!,
            session: QueuedStubURLProtocol.makeSession(),
            tokenProvider: nil
        )

        let widget: Widget = try await client.get("proxy/widget")

        #expect(widget == Widget(name: "Juana Molina"))
        let request = try #require(QueuedStubURLProtocol.capturedRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("WXYCProxyClient authed: attaches the bearer token from the token provider")
    func proxyClientAuthedAttachesBearerToken() async throws {
        QueuedStubURLProtocol.setBody(Data(#"{"name":"Stereolab"}"#.utf8))
        let client = WXYCProxyClient(
            baseURL: URL(string: "https://api.wxyc.org")!,
            session: QueuedStubURLProtocol.makeSession(),
            tokenProvider: RecordingTokenProvider(initialToken: "test-token")
        )

        let widget: Widget = try await client.get("proxy/widget")

        #expect(widget == Widget(name: "Stereolab"))
        let request = try #require(QueuedStubURLProtocol.capturedRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test("WXYCProxyClient composes path + query items into the request URL")
    func proxyClientComposesPathAndQuery() async throws {
        QueuedStubURLProtocol.setBody(Data(#"{"name":"Cat Power"}"#.utf8))
        let client = WXYCProxyClient(
            baseURL: URL(string: "https://api.wxyc.org")!,
            session: QueuedStubURLProtocol.makeSession(),
            tokenProvider: nil
        )

        let _: Widget = try await client.get(
            "proxy/metadata/album",
            query: [
                URLQueryItem(name: "artistName", value: "Cat Power"),
                URLQueryItem(name: "trackTitle", value: "Cross Bone Style"),
            ]
        )

        let request = try #require(QueuedStubURLProtocol.capturedRequest())
        #expect(
            request.url?.absoluteString ==
            "https://api.wxyc.org/proxy/metadata/album?artistName=Cat%20Power&trackTitle=Cross%20Bone%20Style"
        )
    }

    @Test("WXYCProxyClient omits query items entirely, composing a bare path URL with no trailing '?'")
    func proxyClientComposesPathWithNoQuery() async throws {
        QueuedStubURLProtocol.setBody(Data(#"{"name":"Duke Ellington"}"#.utf8))
        let client = WXYCProxyClient(
            baseURL: URL(string: "https://api.wxyc.org")!,
            session: QueuedStubURLProtocol.makeSession(),
            tokenProvider: nil
        )

        let _: Widget = try await client.get("concerts/42")

        let request = try #require(QueuedStubURLProtocol.capturedRequest())
        #expect(request.url?.absoluteString == "https://api.wxyc.org/concerts/42")
    }

    @Test("WXYCProxyClient reauthenticates once and retries when the proxy returns 401")
    func proxyClientRetriesOnceOn401() async throws {
        QueuedStubURLProtocol.setResponses([
            (401, Data()),
            (200, Data(#"{"name":"Jessica Pratt"}"#.utf8)),
        ])
        let tokenProvider = RecordingTokenProvider(initialToken: "stale-token", refreshedToken: "fresh-token")
        let client = WXYCProxyClient(
            baseURL: URL(string: "https://api.wxyc.org")!,
            session: QueuedStubURLProtocol.makeSession(),
            tokenProvider: tokenProvider
        )

        let widget: Widget = try await client.get("proxy/widget")

        #expect(widget == Widget(name: "Jessica Pratt"))
        let headers = QueuedStubURLProtocol.capturedRequests().map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(headers == ["Bearer stale-token", "Bearer fresh-token"])
    }

    @Test("WXYCProxyClient: a non-2xx response surfaces HTTPStatusError instead of decoding the error body")
    func proxyClientNonSuccessStatusThrows() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 502, body: Data(#"{"error":"Bad Gateway"}"#.utf8))
        let client = WXYCProxyClient(
            baseURL: URL(string: "https://api.wxyc.org")!,
            session: QueuedStubURLProtocol.makeSession(),
            tokenProvider: nil
        )

        await #expect(throws: HTTPStatusError(statusCode: 502)) {
            let _: Widget = try await client.get("proxy/widget")
        }
    }

    @Test("WXYCProxyClient.ProxyError.invalidURL carries a human-readable description")
    func proxyClientInvalidURLErrorDescription() {
        #expect(WXYCProxyClient.ProxyError.invalidURL.errorDescription != nil)
    }
}
