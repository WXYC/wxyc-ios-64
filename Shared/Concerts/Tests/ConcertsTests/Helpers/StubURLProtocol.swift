//
//  StubURLProtocol.swift
//  ConcertsTests
//
//  A URLProtocol that captures the outgoing request (so tests can assert on its
//  URL query items and headers) and replies with a fixed 200 body. Unlike the
//  Playlist `CapturingURLProtocol`, this matches any request (the fetcher builds
//  its own query string, so tests can't know the exact URL in advance) and
//  stores the single most-recent captured request.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import os

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var body: Data = Data()
        var captured: URLRequest?
    }

    private static let stateLock = OSAllocatedUnfairLock(initialState: State())

    /// Sets the response body returned to every request and clears the last
    /// captured request.
    static func setBody(_ body: Data) {
        stateLock.withLock {
            $0.body = body
            $0.captured = nil
        }
    }

    /// The most recent request the fetcher issued.
    static func capturedRequest() -> URLRequest? {
        stateLock.withLock { $0.captured }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let snapshot = request
        let body = Self.stateLock.withLock { state -> Data in
            state.captured = snapshot
            return state.body
        }
        let response = HTTPURLResponse(
            url: snapshot.url ?? URL(string: "https://example.invalid")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
