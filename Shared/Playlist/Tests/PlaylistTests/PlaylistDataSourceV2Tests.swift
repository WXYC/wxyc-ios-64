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

// Serialized so the tests don't race on `CapturingURLProtocol`'s URL-keyed
// state — all stub the same URL and read it back, which would otherwise
// overwrite each other when Swift Testing runs them in parallel.
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

    @Test("Decoded playcuts are NOT mojibake-repaired (api.wxyc.org sends well-formed UTF-8)")
    func doesNotApplyMojibakeRepair() async throws {
        // The counterpart of PlaylistDataSourceV1Tests.appliesMojibakeRepair, and
        // the guard on this data source's `repairsMojibake: false`. V1's repair is
        // a workaround for one specific legacy server bug: it re-interprets the
        // decoded string as Latin-1 and re-decodes as UTF-8, which silently
        // rewrites any text that merely *looks* like mojibake. Turning it on for
        // v2 would corrupt listener-visible artist and track names, so the flag
        // must stay off until the tubafrenzy turndown (#262) removes the V1 path
        // entirely. If a future refactor threads `repairsMojibake: true` through
        // to V2 — or defaults the generic transport to repairing — this test
        // fails on the artist-name assertion.
        CapturingURLProtocol.stub(url: URL.WXYCFlowsheet, body: mojibakeFlowsheetBody)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let dataSource = PlaylistDataSourceV2(session: session)
        let playlist = try await dataSource.getPlaylist()

        let playcut = try #require(playlist.playcuts.first)
        #expect(playcut.artistName == "NilÃ¼fer Yanya")
    }
}

// MARK: - Fixtures

private let emptyFlowsheetBody: Data = {
    let json = #"{"entries":[]}"#
    return Data(json.utf8)
}()

private let mojibakeFlowsheetBody: Data = {
    // Byte-for-byte the corruption PlaylistDataSourceV1Tests.mojibakeV1Body
    // describes, on the v2 wire shape. V1 repairs it to "Nilüfer Yanya"; v2 must
    // hand it through untouched.
    let json = #"""
    {"entries":[{"id":1,"entry_type":"track","artist_name":"NilÃ¼fer Yanya","track_title":"In Your Head","album_title":"Painless","play_order":1,"add_time":"2026-08-05T12:00:00Z"}]}
    """#
    return Data(json.utf8)
}()
