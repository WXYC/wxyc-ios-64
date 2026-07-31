//
//  StubURLProtocol.swift
//  ConcertsTests
//
//  A URLProtocol that captures every outgoing request (so tests can assert on
//  URL query items and headers) and replies with a configurable body + status
//  code (200 by default; `setResponse(_:statusCode:)` overrides). Unlike the
//  Playlist `CapturingURLProtocol`, this matches any request (the fetcher builds
//  its own query string, so tests can't know the exact URL in advance).
//
//  `setResponseQueue(_:)` replays one response per request, in order —
//  exhausting the queue repeats its last entry — so a single test can drive
//  multi-request flows like ConcertsFetcher's 401-then-retry reauthentication.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import os

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var responses: [(body: Data, statusCode: Int)] = [(Data(), 200)]
        var captured: [URLRequest] = []
    }

    private static let stateLock = OSAllocatedUnfairLock(initialState: State())

    /// Sets the response body returned to every request and clears the
    /// captured-request log. Resets the status code to 200.
    static func setBody(_ body: Data) {
        stateLock.withLock {
            $0.responses = [(body, 200)]
            $0.captured = []
        }
    }

    /// Sets the response body and the HTTP status code returned to every
    /// request, and clears the captured-request log. Use a non-2xx status to
    /// exercise the fetcher's ``HTTPURLResponse/validateSuccessStatus()`` error
    /// path (mirrors the Metadata package's `MockURLProtocol.responseHandler`
    /// per-status convention).
    static func setResponse(_ body: Data, statusCode: Int) {
        stateLock.withLock {
            $0.responses = [(body, statusCode)]
            $0.captured = []
        }
    }

    /// Sets a queue of responses, replayed one per request in order. A
    /// request past the end of the queue repeats the last entry. Drives
    /// multi-request scenarios such as a 401 followed by a retried 200.
    static func setResponseQueue(_ responses: [(body: Data, statusCode: Int)]) {
        stateLock.withLock {
            $0.responses = responses
            $0.captured = []
        }
    }

    /// The most recent request the fetcher issued.
    static func capturedRequest() -> URLRequest? {
        stateLock.withLock { $0.captured.last }
    }

    /// Every request issued since the last `setBody`/`setResponse`/
    /// `setResponseQueue` call, in order.
    static func capturedRequests() -> [URLRequest] {
        stateLock.withLock { $0.captured }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let snapshot = request
        let (body, statusCode) = Self.stateLock.withLock { state -> (Data, Int) in
            state.captured.append(snapshot)
            let index = min(state.captured.count - 1, state.responses.count - 1)
            return state.responses[index]
        }
        let response = HTTPURLResponse(
            url: snapshot.url ?? URL(string: "https://example.invalid")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
