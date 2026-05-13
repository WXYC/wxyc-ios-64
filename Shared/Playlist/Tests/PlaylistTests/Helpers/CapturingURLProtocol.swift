//
//  CapturingURLProtocol.swift
//  PlaylistTests
//
//  A URLProtocol that captures the outgoing URLRequest and replies with a
//  configurable body. Used by playlist data-source tests to assert on the
//  cachePolicy / timeoutInterval the caller sent.
//
//  Created by Jake Bromberg on 05/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import os

/// A URLProtocol that captures the outgoing URLRequest (so tests can assert on
/// cache policy / timeout) and replies with a configurable body.
///
/// State is keyed by request URL so multiple test suites can use the same
/// protocol class in parallel without interfering with each other. Each test
/// installs a stub for its own URL via `stub(url:body:)` and reads back the
/// captured request with `capturedRequest(for:)`.
///
/// Use via a non-shared `URLSessionConfiguration` with `protocolClasses = [Self.self]`.
final class CapturingURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var bodies: [URL: Data] = [:]
        var captured: [URL: URLRequest] = [:]
    }

    private static let stateLock = OSAllocatedUnfairLock(initialState: State())

    /// Returns the most recent captured `URLRequest` for the given URL, if any.
    static func capturedRequest(for url: URL) -> URLRequest? {
        stateLock.withLock { $0.captured[url] }
    }

    /// Registers a response body to return for requests targeting `url`.
    /// Clears any previously captured request for the same URL.
    static func stub(url: URL, body: Data) {
        stateLock.withLock {
            $0.bodies[url] = body
            $0.captured[url] = nil
        }
    }

    /// Clears all stubs and captured state. Tests should not normally need this;
    /// use `stub(url:body:)` per-URL to keep parallel suites isolated.
    static func resetAll() {
        stateLock.withLock {
            $0.bodies.removeAll()
            $0.captured.removeAll()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return stateLock.withLock { $0.bodies[url] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession hands us the *original* URLRequest, including the cachePolicy
        // and timeoutInterval the caller specified. Stash it for inspection.
        let snapshot = request
        let url = snapshot.url ?? URL(string: "https://example.invalid")!
        let body = Self.stateLock.withLock { state -> Data in
            state.captured[url] = snapshot
            return state.bodies[url] ?? Data()
        }
        let response = HTTPURLResponse(
            url: url,
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
