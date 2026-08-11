//
//  PatternRoutingWebSessionTests.swift
//  Core
//
//  Tests for CoreTesting's `PatternRoutingWebSession`: an ergonomic facade
//  over `QueuedStubURLProtocol`'s handler mode for tests that stub several
//  endpoints by URL substring and read back requestCount/requestedURLs — the
//  same test-facing shape the retired per-package `WebSession`-conforming
//  mocks (Metadata's `MetadataMockWebSession`/`MetadataV2MockWebSession`)
//  hand-rolled before #786 folded them here.
//
//  Declared as an extension of `AuthedDataTests` (`AuthedDataTests.swift`)
//  rather than its own `@Suite`: `PatternRoutingWebSession` delegates to
//  `QueuedStubURLProtocol`'s single registered class, so it inherits that
//  type's one-adopter-per-bundle constraint (see both types' header docs) —
//  the same reason `WXYCProxyClientTests.swift` extends this suite instead of
//  declaring its own.
//
//  Created by Jake Bromberg on 08/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreTesting
import Foundation
import Testing

extension AuthedDataTests {

    @Test("Routes a response to a request whose URL contains the matching pattern")
    func patternRoutingReturnsMatchedBody() async throws {
        let session = PatternRoutingWebSession()
        session.responses["widgets"] = Data(#"{"name":"Juana Molina"}"#.utf8)

        let (data, _) = try await session.urlSession.data(from: URL(string: "https://api.wxyc.test/widgets/1")!)

        #expect(String(data: data, encoding: .utf8) == #"{"name":"Juana Molina"}"#)
    }

    @Test("Routes multiple patterns to their own responses independently")
    func patternRoutingDisambiguatesMultiplePatterns() async throws {
        let session = PatternRoutingWebSession()
        session.responses["widgets"] = Data(#"{"kind":"widget"}"#.utf8)
        session.responses["gadgets"] = Data(#"{"kind":"gadget"}"#.utf8)

        let (widgetData, _) = try await session.urlSession.data(from: URL(string: "https://api.wxyc.test/widgets/1")!)
        let (gadgetData, _) = try await session.urlSession.data(from: URL(string: "https://api.wxyc.test/gadgets/1")!)

        #expect(String(data: widgetData, encoding: .utf8) == #"{"kind":"widget"}"#)
        #expect(String(data: gadgetData, encoding: .utf8) == #"{"kind":"gadget"}"#)
    }

    @Test("Fails a request matching no configured pattern, rather than hanging or reaching the network")
    func patternRoutingFailsUnmatchedRequest() async throws {
        let session = PatternRoutingWebSession()
        session.responses["widgets"] = Data()

        do {
            _ = try await session.urlSession.data(from: URL(string: "https://api.wxyc.test/gadgets/1")!)
            Issue.record("Expected the request to fail")
        } catch let error as URLError {
            #expect(error.code == .resourceUnavailable)
        }
    }

    @Test("Tracks requestCount and requestedURLs across multiple requests, including unmatched ones")
    func patternRoutingTracksAllRequests() async throws {
        let session = PatternRoutingWebSession()
        session.responses["widgets"] = Data("{}".utf8)

        _ = try await session.urlSession.data(from: URL(string: "https://api.wxyc.test/widgets/1")!)
        _ = try? await session.urlSession.data(from: URL(string: "https://api.wxyc.test/unmatched")!)

        #expect(session.requestCount == 2, "Unmatched requests still count — they were observed, just not served")
        #expect(session.requestedURLs.map(\.path) == ["/widgets/1", "/unmatched"])
    }

    @Test("reset() clears configured responses and the captured-request log")
    func patternRoutingResetClearsState() async throws {
        let session = PatternRoutingWebSession()
        session.responses["widgets"] = Data("{}".utf8)
        _ = try await session.urlSession.data(from: URL(string: "https://api.wxyc.test/widgets/1")!)
        #expect(session.requestCount == 1)

        session.reset()

        #expect(session.requestCount == 0)
        do {
            _ = try await session.urlSession.data(from: URL(string: "https://api.wxyc.test/widgets/1")!)
            Issue.record("Expected the request to fail — reset() must clear configured responses too")
        } catch let error as URLError {
            #expect(error.code == .resourceUnavailable)
        }
    }

    @Test("A newly constructed session replaces whatever the previous instance installed")
    func patternRoutingNewInstanceReplacesPrevious() async throws {
        let first = PatternRoutingWebSession()
        first.responses["widgets"] = Data("first".utf8)

        let second = PatternRoutingWebSession()
        second.responses["widgets"] = Data("second".utf8)

        // Both instances share `QueuedStubURLProtocol`'s single registered
        // class, so only the most recently constructed instance is "live" —
        // exactly the one-adopter-per-bundle constraint this type inherits.
        let (data, _) = try await second.urlSession.data(from: URL(string: "https://api.wxyc.test/widgets/1")!)
        #expect(String(data: data, encoding: .utf8) == "second")
    }
}
