//
//  PatternRoutingWebSession.swift
//  CoreTesting
//
//  An ergonomic facade over `QueuedStubURLProtocol`'s handler mode for tests
//  that want to stub several endpoints by URL substring and read back
//  requestCount/requestedURLs — the same test-facing shape the retired
//  per-package `WebSession`-conforming mocks (Metadata's
//  `MetadataMockWebSession`/`MetadataV2MockWebSession`) hand-rolled before
//  #786 folded them here.
//
//  This type owns no static state and registers no `URLProtocol` of its own:
//  every request still flows through `QueuedStubURLProtocol`'s single
//  registered class, so it inherits — rather than escapes — that type's
//  one-adopter-per-bundle constraint (see its header doc). Constructing a
//  `PatternRoutingWebSession` replaces whatever handler a previous instance
//  installed, so only the most-recently-constructed instance in a test
//  bundle is "live" at any moment. That is exactly the "one live instance at
//  a time, fresh per test" shape every adopting suite already uses
//  `QueuedStubURLProtocol` for directly — this type just adds
//  `responses[pattern] = body` sugar and per-instance request tracking on
//  top, so a suite with several tests needing multi-endpoint pattern routing
//  doesn't hand-roll its own `URLProtocol` subclass to get it.
//
//  Created by Jake Bromberg on 08/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import os

/// A `QueuedStubURLProtocol`-backed test double that routes responses by
/// substring-matching the outgoing request's URL, and tracks every request
/// observed since construction or the last `reset()`.
///
/// See the file header for why this shares `QueuedStubURLProtocol`'s
/// one-adopter-per-bundle constraint despite being an instantiable type.
public final class PatternRoutingWebSession: @unchecked Sendable {
    private struct State {
        var responses: [String: Data] = [:]
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    /// Response bodies keyed by a substring to match against the outgoing
    /// request's URL. The first matching entry (dictionary iteration order
    /// is unspecified) wins; a request matching no entry fails with
    /// `.resourceUnavailable` rather than hanging or reaching the network.
    public var responses: [String: Data] {
        get { stateLock.withLock { $0.responses } }
        set { stateLock.withLock { $0.responses = newValue } }
    }

    /// Every request URL observed since construction or the last `reset()`, in order.
    public var requestedURLs: [URL] {
        QueuedStubURLProtocol.capturedRequests().compactMap(\.url)
    }

    /// The number of requests observed since construction or the last `reset()`.
    public var requestCount: Int { requestedURLs.count }

    /// The `URLSession` to inject into the code under test.
    public let urlSession = QueuedStubURLProtocol.makeSession()

    public init() {
        installHandler()
    }

    /// Clears configured responses and the captured-request log.
    public func reset() {
        stateLock.withLock { $0 = State() }
        installHandler()
    }

    private func installHandler() {
        QueuedStubURLProtocol.setHandler { [stateLock] request in
            let urlString = request.url?.absoluteString ?? ""
            guard let matched = stateLock.withLock({ $0.responses.first { urlString.contains($0.key) }?.value }) else {
                throw URLError(.resourceUnavailable)
            }
            guard let url = request.url, let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else {
                throw URLError(.badURL)
            }
            return (matched, response)
        }
    }
}
