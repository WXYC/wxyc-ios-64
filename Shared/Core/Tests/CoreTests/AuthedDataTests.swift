//
//  AuthedDataTests.swift
//  Core
//
//  Tests for `URLSession.authedData(for:tokenProvider:)`: the shared
//  authed-request seam that attaches a bearer token and retries once on a
//  401 after forcing a fresh token. Uses CoreTesting's
//  `QueuedStubURLProtocol` so successive requests can return different
//  status codes without touching the network.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreTesting
import Foundation
import Testing
@testable import Core

@Suite("URLSession.authedData", .serialized)
struct AuthedDataTests {

    private static let resourceURL = URL(string: "https://api.wxyc.test/resource")!

    @Test("A 200 response with a token provider attaches the bearer token and issues no retry")
    func successAttachesTokenNoRetry() async throws {
        QueuedStubURLProtocol.setResponses([(200, Data("ok".utf8))])
        let tokenProvider = RecordingTokenProvider()
        let session = QueuedStubURLProtocol.makeSession()

        let (data, response) = try await session.authedData(
            for: URLRequest(url: Self.resourceURL),
            tokenProvider: tokenProvider
        )

        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        let requests = QueuedStubURLProtocol.capturedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer initial-token")
        #expect(await tokenProvider.reauthenticateCallCount == 0)
    }

    @Test("A 401 reauthenticates once and retries with the fresh token")
    func retriesOnceOn401ThenSucceeds() async throws {
        QueuedStubURLProtocol.setResponses([
            (401, Data()),
            (200, Data("ok".utf8)),
        ])
        let tokenProvider = RecordingTokenProvider()
        let session = QueuedStubURLProtocol.makeSession()

        let (data, response) = try await session.authedData(
            for: URLRequest(url: Self.resourceURL),
            tokenProvider: tokenProvider
        )

        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(await tokenProvider.reauthenticateCallCount == 1)
        #expect(await tokenProvider.lastPreviousToken == "initial-token")

        let requests = QueuedStubURLProtocol.capturedRequests()
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer initial-token")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token")
    }

    @Test("Two consecutive 401s surface HTTPStatusError(401) without a second retry")
    func doesNotRetryTwice() async throws {
        QueuedStubURLProtocol.setResponses([
            (401, Data()),
            (401, Data()),
        ])
        let tokenProvider = RecordingTokenProvider()
        let session = QueuedStubURLProtocol.makeSession()

        await #expect(throws: HTTPStatusError(statusCode: 401)) {
            _ = try await session.authedData(
                for: URLRequest(url: Self.resourceURL),
                tokenProvider: tokenProvider
            )
        }

        #expect(QueuedStubURLProtocol.capturedRequests().count == 2)
        #expect(await tokenProvider.reauthenticateCallCount == 1)
    }

    @Test("A nil token provider sends no Authorization header and never retries")
    func nilTokenProviderSkipsAuthAndRetry() async throws {
        QueuedStubURLProtocol.setResponses([(401, Data())])
        let session = QueuedStubURLProtocol.makeSession()

        await #expect(throws: HTTPStatusError(statusCode: 401)) {
            _ = try await session.authedData(
                for: URLRequest(url: Self.resourceURL),
                tokenProvider: nil
            )
        }

        let requests = QueuedStubURLProtocol.capturedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A non-HTTP response throws URLError(.badServerResponse) instead of escaping unvalidated")
    func nonHTTPResponseThrows() async throws {
        // The doc guarantees callers a status-validated `HTTPURLResponse`;
        // a transport that yields a plain `URLResponse` must throw rather
        // than hand back an unvalidated response.
        let session = QueuedStubURLProtocol.session { request in
            (Data(), URLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil
            ))
        }

        await #expect(throws: URLError(.badServerResponse)) {
            _ = try await session.authedData(
                for: URLRequest(url: Self.resourceURL),
                tokenProvider: nil
            )
        }
    }

    @Test("A caller cancelled during reauthentication does not issue the doomed retry", .timeLimit(.minutes(1)))
    func cancelledCallerSkipsRetry() async throws {
        QueuedStubURLProtocol.setResponses([(401, Data())])
        let tokenProvider = RecordingTokenProvider(gateReauthentication: true)
        let session = QueuedStubURLProtocol.makeSession()

        let task = Task {
            try await session.authedData(
                for: URLRequest(url: Self.resourceURL),
                tokenProvider: tokenProvider
            )
        }

        // Wait until the caller is parked inside the (shared, non-cancellable)
        // reauthentication, then cancel it and let the reauthentication finish.
        while await !tokenProvider.reauthenticateStarted {
            await Task.yield()
        }
        task.cancel()
        await tokenProvider.release()

        // The cancelled caller must surface CancellationError without paying
        // for a retry request whose result nobody will read.
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(QueuedStubURLProtocol.capturedRequests().count == 1)
    }
}
