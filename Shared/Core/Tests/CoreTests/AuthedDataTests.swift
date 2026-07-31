//
//  AuthedDataTests.swift
//  Core
//
//  Tests for `URLSession.authedData(for:tokenProvider:)`: the shared
//  authed-request seam that attaches a bearer token and retries once on a
//  401 after forcing a fresh token. Uses a queued stub `URLProtocol` so
//  successive requests can return different status codes without touching
//  the network.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import os
@testable import Core

@Suite("URLSession.authedData", .serialized)
struct AuthedDataTests {

    private static func makeSession(
        protocolClass: URLProtocol.Type = SequencedStubURLProtocol.self
    ) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [protocolClass]
        return URLSession(configuration: config)
    }

    private static let resourceURL = URL(string: "https://api.wxyc.test/resource")!

    @Test("A 200 response with a token provider attaches the bearer token and issues no retry")
    func successAttachesTokenNoRetry() async throws {
        SequencedStubURLProtocol.setResponses([(200, Data("ok".utf8))])
        let tokenProvider = StubTokenProvider()
        let session = Self.makeSession()

        let (data, response) = try await session.authedData(
            for: URLRequest(url: Self.resourceURL),
            tokenProvider: tokenProvider
        )

        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        let requests = SequencedStubURLProtocol.capturedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer initial-token")
        #expect(await tokenProvider.reauthenticateCallCount == 0)
    }

    @Test("A 401 reauthenticates once and retries with the fresh token")
    func retriesOnceOn401ThenSucceeds() async throws {
        SequencedStubURLProtocol.setResponses([
            (401, Data()),
            (200, Data("ok".utf8)),
        ])
        let tokenProvider = StubTokenProvider()
        let session = Self.makeSession()

        let (data, response) = try await session.authedData(
            for: URLRequest(url: Self.resourceURL),
            tokenProvider: tokenProvider
        )

        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(await tokenProvider.reauthenticateCallCount == 1)
        #expect(await tokenProvider.lastPreviousToken == "initial-token")

        let requests = SequencedStubURLProtocol.capturedRequests()
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer initial-token")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token")
    }

    @Test("Two consecutive 401s surface HTTPStatusError(401) without a second retry")
    func doesNotRetryTwice() async throws {
        SequencedStubURLProtocol.setResponses([
            (401, Data()),
            (401, Data()),
        ])
        let tokenProvider = StubTokenProvider()
        let session = Self.makeSession()

        await #expect(throws: HTTPStatusError(statusCode: 401)) {
            _ = try await session.authedData(
                for: URLRequest(url: Self.resourceURL),
                tokenProvider: tokenProvider
            )
        }

        #expect(SequencedStubURLProtocol.capturedRequests().count == 2)
        #expect(await tokenProvider.reauthenticateCallCount == 1)
    }

    @Test("A nil token provider sends no Authorization header and never retries")
    func nilTokenProviderSkipsAuthAndRetry() async throws {
        SequencedStubURLProtocol.setResponses([(401, Data())])
        let session = Self.makeSession()

        await #expect(throws: HTTPStatusError(statusCode: 401)) {
            _ = try await session.authedData(
                for: URLRequest(url: Self.resourceURL),
                tokenProvider: nil
            )
        }

        let requests = SequencedStubURLProtocol.capturedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A non-HTTP response throws URLError(.badServerResponse) instead of escaping unvalidated")
    func nonHTTPResponseThrows() async throws {
        // The doc guarantees callers a status-validated `HTTPURLResponse`;
        // a transport that yields a plain `URLResponse` must throw rather
        // than hand back an unvalidated response.
        let session = Self.makeSession(protocolClass: PlainResponseStubURLProtocol.self)

        await #expect(throws: URLError(.badServerResponse)) {
            _ = try await session.authedData(
                for: URLRequest(url: Self.resourceURL),
                tokenProvider: nil
            )
        }
    }

    @Test("A caller cancelled during reauthentication does not issue the doomed retry", .timeLimit(.minutes(1)))
    func cancelledCallerSkipsRetry() async throws {
        SequencedStubURLProtocol.setResponses([(401, Data())])
        let tokenProvider = GatedTokenProvider()
        let session = Self.makeSession()

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
        #expect(SequencedStubURLProtocol.capturedRequests().count == 1)
    }
}

// MARK: - Stub URLProtocol

/// Replays one queued `(statusCode, body)` response per request, in order.
/// A request past the end of the queue repeats the last entry.
private final class SequencedStubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var responses: [(statusCode: Int, body: Data)] = [(200, Data())]
        var captured: [URLRequest] = []
    }

    private static let stateLock = OSAllocatedUnfairLock(initialState: State())

    /// Sets the queue of responses and clears the captured-request log.
    static func setResponses(_ responses: [(statusCode: Int, body: Data)]) {
        precondition(!responses.isEmpty, "setResponses requires at least one response — an empty queue would trap on the first request")
        stateLock.withLock {
            $0.responses = responses
            $0.captured = []
        }
    }

    /// Every request issued since the last `setResponses(_:)` call, in order.
    static func capturedRequests() -> [URLRequest] {
        stateLock.withLock { $0.captured }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let snapshot = request
        let entry = Self.stateLock.withLock { state -> (statusCode: Int, body: Data) in
            state.captured.append(snapshot)
            let index = min(state.captured.count - 1, state.responses.count - 1)
            return state.responses[index]
        }
        let response = HTTPURLResponse(
            url: snapshot.url ?? URL(string: "https://example.invalid")!,
            statusCode: entry.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: entry.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Replies to every request with a plain (non-HTTP) `URLResponse`, driving
/// the seam's guard against transports that can't be status-validated.
private final class PlainResponseStubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = URLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Stub token providers

/// Returns a fixed `token()` and a fixed (different) `reauthenticate(previousToken:)`
/// value, so tests can assert the retried request carried the *new* token.
/// Tracks call counts and the `previousToken` it was given for assertions.
private actor StubTokenProvider: SessionTokenProvider {
    private(set) var reauthenticateCallCount = 0
    private(set) var lastPreviousToken: String?
    private let initialToken: String
    private let refreshedToken: String

    init(initialToken: String = "initial-token", refreshedToken: String = "refreshed-token") {
        self.initialToken = initialToken
        self.refreshedToken = refreshedToken
    }

    func token() async throws -> String {
        initialToken
    }

    func reauthenticate(previousToken: String) async throws -> String {
        lastPreviousToken = previousToken
        reauthenticateCallCount += 1
        return refreshedToken
    }
}

/// A `SessionTokenProvider` whose `reauthenticate(previousToken:)` suspends
/// until `release()` is called, so a test can cancel the caller while its
/// reauthentication is still in flight.
private actor GatedTokenProvider: SessionTokenProvider {
    private(set) var reauthenticateStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func token() async throws -> String { "initial-token" }

    func reauthenticate(previousToken: String) async throws -> String {
        reauthenticateStarted = true
        if !released {
            await withCheckedContinuation { waiters.append($0) }
        }
        return "refreshed-token"
    }

    func release() {
        released = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}
