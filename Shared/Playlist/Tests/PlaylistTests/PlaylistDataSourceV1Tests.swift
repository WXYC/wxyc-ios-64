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

// Serialized so the two tests don't race on `CapturingURLProtocol`'s
// URL-keyed state — both stub the same URL and read it back, which would
// otherwise overwrite each other when Swift Testing runs them in parallel.
@Suite("PlaylistDataSourceV1 Tests", .serialized)
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

    @Test("Decoded playcuts have mojibake-repaired strings (the legacy V1 server can double-encode UTF-8 as Latin-1)")
    func appliesMojibakeRepair() async throws {
        // The legacy tubafrenzy server has historically emitted UTF-8 strings
        // double-encoded ("NilÃ¼fer Yanya" instead of "Nilüfer Yanya"). The
        // data source must run repairingMojibake() before JSON decoding so
        // downstream consumers see the original text. If a future refactor
        // drops that step this test fails on the artist-name assertion.
        CapturingURLProtocol.stub(url: URL.WXYCPlaylist, body: mojibakeV1Body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let dataSource = PlaylistDataSourceV1(session: session)
        let playlist = try await dataSource.getPlaylist()

        let playcut = try #require(playlist.playcuts.first)
        #expect(playcut.artistName == "Nilüfer Yanya")
    }
}

// MARK: - Fixtures

private let emptyV1Body: Data = {
    let json = #"{"playcuts":[],"breakpoints":[],"talksets":[]}"#
    return Data(json.utf8)
}()

private let mojibakeV1Body: Data = {
    // "NilÃ¼fer Yanya" is the mojibake encoding of "Nilüfer Yanya":
    // the original UTF-8 bytes (C3 BC for ü) re-interpreted as Latin-1
    // (Ã + ¼) and then re-encoded as UTF-8 (C3 83 C2 BC). That's what
    // tubafrenzy emits today and what `repairingMojibake()` reverses.
    let json = #"""
    {"playcuts":[{"id":1,"rotation":"false","request":"false","songTitle":"In Your Head","timeCreated":0,"labelName":"ATO Records","hour":0,"artistName":"NilÃ¼fer Yanya","chronOrderID":1,"releaseTitle":"Painless"}],"breakpoints":[],"talksets":[]}
    """#
    return Data(json.utf8)
}()
