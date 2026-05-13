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
@testable import Playlist

// MARK: - PlaylistDataSourceV2 Tests

// Serialized so the two tests don't race on `CapturingURLProtocol`'s
// URL-keyed state — both stub the same URL and read it back, which would
// otherwise overwrite each other when Swift Testing runs them in parallel.
@Suite("PlaylistDataSourceV2 Tests", .serialized)
struct PlaylistDataSourceV2Tests {
    @Test("Uses reloadRevalidatingCacheData cache policy so URLCache.shared cannot serve a stale playlist on relaunch")
    func usesRevalidatingCachePolicy() async throws {
        CapturingURLProtocol.stub(url: URL.WXYCFlowsheet, body: emptyFlowsheetBody)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let dataSource = PlaylistDataSourceV2(session: session)
        _ = try await dataSource.getPlaylist()

        let request = try #require(CapturingURLProtocol.capturedRequest(for: URL.WXYCFlowsheet))
        #expect(request.cachePolicy == .reloadRevalidatingCacheData)
        #expect(request.url == URL.WXYCFlowsheet)
    }

    @Test("Sets a finite request timeout so a hung poll cannot block the next one indefinitely")
    func setsFiniteTimeout() async throws {
        CapturingURLProtocol.stub(url: URL.WXYCFlowsheet, body: emptyFlowsheetBody)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let dataSource = PlaylistDataSourceV2(session: session)
        _ = try await dataSource.getPlaylist()

        let request = try #require(CapturingURLProtocol.capturedRequest(for: URL.WXYCFlowsheet))
        #expect(request.timeoutInterval > 0)
        #expect(request.timeoutInterval <= 60)
    }
}

// MARK: - Fixtures

private let emptyFlowsheetBody: Data = {
    let json = #"{"entries":[]}"#
    return Data(json.utf8)
}()
