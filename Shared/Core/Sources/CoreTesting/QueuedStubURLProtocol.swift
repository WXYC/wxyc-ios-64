//
//  QueuedStubURLProtocol.swift
//  CoreTesting
//
//  The canonical stub `URLProtocol`. Replaces the per-target clones that
//  drifted apart: CoreTests' `SequencedStubURLProtocol` and
//  `PlainResponseStubURLProtocol`, ConcertsTests' `StubURLProtocol`,
//  MetadataTests' `MockURLProtocol` (`responseHandler`), and
//  AppServicesTests' `MockURLProtocol` (`handler`/`session(handler:)`).
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import os

/// Stubs URLSession traffic for tests without touching the network, in one of
/// two modes:
///
/// - **Queue mode** (`setResponses(_:)` and its conveniences): replays one
///   queued `(statusCode, body)` HTTP response per request, in order — a
///   request past the end of the queue repeats the last entry. Drives
///   multi-request flows like a 401 followed by a retried 200.
/// - **Handler mode** (`setHandler(_:)` / `session(handler:)`): runs an
///   arbitrary per-request closure, for responses the queue can't express —
///   per-URL routing, thrown transport errors, or a plain non-HTTP
///   `URLResponse` (the former `PlainResponseStubURLProtocol` case).
///
/// Every request is captured for assertion via `capturedRequests()`,
/// whichever mode is active.
///
/// State is static — `URLProtocol` registration is by class, not instance —
/// so no two tests touching this type may run concurrently. The adopting
/// suite's `.serialized` trait is necessary but not sufficient: traits only
/// serialize tests *within* a suite, and a second adopting `@Suite` in the
/// same test bundle would still run in parallel with the first. Keep at most
/// one adopting suite per test bundle, and add further adopting tests as an
/// `extension` of that suite — see the 401 retry test in
/// `DiscogsAPIEntityResolverCachingTests.swift`, declared as an extension of
/// `PlaycutMetadataServiceHTTPTests` for exactly this reason.
public final class QueuedStubURLProtocol: URLProtocol, @unchecked Sendable {

    private struct State {
        var handler: (@Sendable (URLRequest) throws -> (Data, URLResponse))?
        var responses: [(statusCode: Int, body: Data)] = [(200, Data())]
        var captured: [URLRequest] = []
    }

    private static let stateLock = OSAllocatedUnfairLock(initialState: State())

    // MARK: - Queue mode

    /// Sets the queue of responses, replayed one per request in order (a
    /// request past the end repeats the last entry), clears any handler, and
    /// resets the captured-request log.
    public static func setResponses(_ responses: [(statusCode: Int, body: Data)]) {
        precondition(!responses.isEmpty, "setResponses requires at least one response — an empty queue would trap on the first request")
        stateLock.withLock {
            $0.handler = nil
            $0.responses = responses
            $0.captured = []
        }
    }

    /// Sets a single response returned to every request.
    public static func setResponse(statusCode: Int, body: Data = Data()) {
        setResponses([(statusCode, body)])
    }

    /// Sets a single 200 response with the given body.
    public static func setBody(_ body: Data) {
        setResponses([(200, body)])
    }

    // MARK: - Handler mode

    /// Routes every request through `handler` instead of the queue, and
    /// resets the captured-request log. A thrown error fails the request
    /// (`URLSession` surfaces it as the request's error).
    public static func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)) {
        stateLock.withLock {
            $0.handler = handler
            $0.captured = []
        }
    }

    /// Creates an ephemeral `URLSession` backed by this protocol and installs
    /// `handler` in one step.
    public static func session(handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)) -> URLSession {
        setHandler(handler)
        return makeSession()
    }

    // MARK: - Session factory & capture

    /// Creates an ephemeral `URLSession` whose traffic this protocol
    /// intercepts.
    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QueuedStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Every request issued since the last `setResponses`/`setHandler` (or
    /// convenience) call, in order.
    public static func capturedRequests() -> [URLRequest] {
        stateLock.withLock { $0.captured }
    }

    /// The most recent captured request.
    public static func capturedRequest() -> URLRequest? {
        stateLock.withLock { $0.captured.last }
    }

    // MARK: - URLProtocol

    override public class func canInit(with request: URLRequest) -> Bool { true }
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        let snapshot = request
        let mode = Self.stateLock.withLock { state -> (handler: (@Sendable (URLRequest) throws -> (Data, URLResponse))?, entry: (statusCode: Int, body: Data)) in
            state.captured.append(snapshot)
            if let handler = state.handler {
                return (handler, (200, Data()))
            }
            let index = min(state.captured.count - 1, state.responses.count - 1)
            return (nil, state.responses[index])
        }

        if let handler = mode.handler {
            do {
                let (data, response) = try handler(snapshot)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
            return
        }

        guard let url = snapshot.url, let response = HTTPURLResponse(
            url: url,
            statusCode: mode.entry.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mode.entry.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}
}
