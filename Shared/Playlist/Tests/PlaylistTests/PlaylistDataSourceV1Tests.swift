//
//  PlaylistDataSourceV1Tests.swift
//  Playlist
//
//  Tests for PlaylistDataSourceV1, including HTTP cache policy assertions.
//
//  Created by Jake Bromberg on 05/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

// MARK: - PlaylistDataSourceV1 Tests

@Suite("PlaylistDataSourceV1 Tests")
struct PlaylistDataSourceV1Tests {
    @Test("Uses reloadRevalidatingCacheData cache policy so URLCache.shared cannot serve a stale playlist on relaunch")
    func usesRevalidatingCachePolicy() async throws {
        CapturingURLProtocol.stub(url: URL.WXYCPlaylist, body: emptyV1Body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let dataSource = PlaylistDataSourceV1(session: session)
        _ = try await dataSource.getPlaylist()

        let request = try #require(CapturingURLProtocol.capturedRequest(for: URL.WXYCPlaylist))
        #expect(request.cachePolicy == .reloadRevalidatingCacheData)
        #expect(request.url == URL.WXYCPlaylist)
    }

    @Test("Sets a finite request timeout so a hung poll cannot block the next one indefinitely")
    func setsFiniteTimeout() async throws {
        CapturingURLProtocol.stub(url: URL.WXYCPlaylist, body: emptyV1Body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let dataSource = PlaylistDataSourceV1(session: session)
        _ = try await dataSource.getPlaylist()

        let request = try #require(CapturingURLProtocol.capturedRequest(for: URL.WXYCPlaylist))
        #expect(request.timeoutInterval > 0)
        #expect(request.timeoutInterval <= 60)
    }
}

// MARK: - Fixtures

private let emptyV1Body: Data = {
    let json = #"{"playcuts":[],"breakpoints":[],"talksets":[]}"#
    return Data(json.utf8)
}()
