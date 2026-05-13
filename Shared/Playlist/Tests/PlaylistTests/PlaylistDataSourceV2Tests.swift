//
//  PlaylistDataSourceV2Tests.swift
//  Playlist
//
//  Tests for PlaylistDataSourceV2, including HTTP cache policy assertions.
//
//  Created by Jake Bromberg on 05/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import os
@testable import Playlist

// MARK: - PlaylistDataSourceV2 Tests

@Suite("PlaylistDataSourceV2 Tests", .serialized)
struct PlaylistDataSourceV2Tests {
    @Test("Uses reloadRevalidatingCacheData cache policy so URLCache.shared cannot serve a stale playlist on relaunch")
    func usesRevalidatingCachePolicy() async throws {
        CapturingURLProtocol.reset()
        CapturingURLProtocol.setResponseBody(emptyFlowsheetBody)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let dataSource = PlaylistDataSourceV2(session: session)
        _ = try await dataSource.getPlaylist()

        let request = try #require(CapturingURLProtocol.capturedRequest)
        #expect(request.cachePolicy == .reloadRevalidatingCacheData)
        #expect(request.url == URL.WXYCFlowsheet)
    }

    @Test("Sets a finite request timeout so a hung poll cannot block the next one indefinitely")
    func setsFiniteTimeout() async throws {
        CapturingURLProtocol.reset()
        CapturingURLProtocol.setResponseBody(emptyFlowsheetBody)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let dataSource = PlaylistDataSourceV2(session: session)
        _ = try await dataSource.getPlaylist()

        let request = try #require(CapturingURLProtocol.capturedRequest)
        #expect(request.timeoutInterval > 0)
        #expect(request.timeoutInterval <= 60)
    }
}

// MARK: - Fixtures

private let emptyFlowsheetBody: Data = {
    let json = #"{"entries":[]}"#
    return Data(json.utf8)
}()

// MARK: - CapturingURLProtocol

/// A URLProtocol that captures the outgoing URLRequest (so tests can assert on
/// cache policy / timeout) and replies with a configurable body.
///
/// Use via a non-shared `URLSessionConfiguration` with `protocolClasses = [Self.self]`.
final class CapturingURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var captured: URLRequest?
        var responseBody: Data = Data()
    }

    private static let stateLock = OSAllocatedUnfairLock(initialState: State())

    static var capturedRequest: URLRequest? {
        stateLock.withLock { $0.captured }
    }

    static func setResponseBody(_ body: Data) {
        stateLock.withLock { $0.responseBody = body }
    }

    static func reset() {
        stateLock.withLock {
            $0.captured = nil
            $0.responseBody = Data()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession hands us the *original* URLRequest, including the cachePolicy
        // and timeoutInterval the caller specified. Stash it for inspection.
        let snapshot = request
        let body = Self.stateLock.withLock { state -> Data in
            state.captured = snapshot
            return state.responseBody
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
