//
//  RevalidatingJSONDataSourceTests.swift
//  Playlist
//
//  Tests for RevalidatingJSONDataSource, the generic transport PlaylistDataSourceV1
//  and PlaylistDataSourceV2 both delegate to (#769): URL + cache policy + timeout
//  + status validation + decode, parameterized on the wire Response type and a
//  Response -> Playlist map.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

// Serialized for the same reason as PlaylistDataSourceV1Tests/V2Tests: all
// stub the same CapturingURLProtocol-keyed URL and read it back.
@Suite("RevalidatingJSONDataSource Tests", .serialized)
struct RevalidatingJSONDataSourceTests {
    private static let testURL = URL(string: "https://example.invalid/revalidating-json-data-source-tests")!

    @Test("Uses reloadRevalidatingCacheData cache policy so URLCache.shared cannot serve a stale playlist on relaunch")
    func usesRevalidatingCachePolicy() async throws {
        CapturingURLProtocol.stub(url: Self.testURL, body: emptyPlaylistBody)
        let dataSource = RevalidatingJSONDataSource<Playlist>(url: Self.testURL, session: makeSession(), map: { $0 })

        _ = try await dataSource.getPlaylist()

        let request = try #require(CapturingURLProtocol.capturedRequest(for: Self.testURL))
        #expect(request.cachePolicy == .reloadRevalidatingCacheData)
        #expect(request.url == Self.testURL)
    }

    @Test("Sets a finite request timeout so a hung poll cannot block the next one indefinitely")
    func setsFiniteTimeout() async throws {
        CapturingURLProtocol.stub(url: Self.testURL, body: emptyPlaylistBody)
        let dataSource = RevalidatingJSONDataSource<Playlist>(url: Self.testURL, session: makeSession(), map: { $0 })

        _ = try await dataSource.getPlaylist()

        let request = try #require(CapturingURLProtocol.capturedRequest(for: Self.testURL))
        #expect(request.timeoutInterval > 0)
        #expect(request.timeoutInterval <= 60)
    }

    @Test("Decodes the wire Response and applies the caller's map to produce a Playlist")
    func decodesAndMaps() async throws {
        CapturingURLProtocol.stub(url: Self.testURL, body: Data(#"{"count":3}"#.utf8))
        let dataSource = RevalidatingJSONDataSource<EntryCount>(
            url: Self.testURL,
            session: makeSession(),
            map: { response in
                Playlist(
                    playcuts: (0..<response.count).map { .stub(id: UInt64($0)) },
                    breakpoints: [],
                    talksets: []
                )
            }
        )

        let playlist = try await dataSource.getPlaylist()
        #expect(playlist.playcuts.count == 3)
    }

    @Test("repairsMojibake: true repairs UTF-8-as-Latin-1 corruption before decoding")
    func repairsMojibakeWhenEnabled() async throws {
        CapturingURLProtocol.stub(url: Self.testURL, body: mojibakePlaylistBody)
        let dataSource = RevalidatingJSONDataSource<Playlist>(
            url: Self.testURL,
            session: makeSession(),
            repairsMojibake: true,
            map: { $0 }
        )

        let playlist = try await dataSource.getPlaylist()
        let playcut = try #require(playlist.playcuts.first)
        #expect(playcut.artistName == "Nilüfer Yanya")
    }

    @Test("repairsMojibake: false (the default) leaves mojibake-corrupted text uncorrected")
    func leavesMojibakeUncorrectedByDefault() async throws {
        CapturingURLProtocol.stub(url: Self.testURL, body: mojibakePlaylistBody)
        let dataSource = RevalidatingJSONDataSource<Playlist>(url: Self.testURL, session: makeSession(), map: { $0 })

        let playlist = try await dataSource.getPlaylist()
        let playcut = try #require(playlist.playcuts.first)
        #expect(playcut.artistName == "NilÃ¼fer Yanya")
    }
}

// MARK: - Fixtures

/// Minimal response shape distinct from `Playlist`, proving the map runs on
/// the declared `Response` type rather than assuming `Response == Playlist`.
private struct EntryCount: Decodable {
    let count: Int
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CapturingURLProtocol.self]
    return URLSession(configuration: configuration)
}

private let emptyPlaylistBody: Data = {
    let json = #"{"playcuts":[],"breakpoints":[],"talksets":[]}"#
    return Data(json.utf8)
}()

private let mojibakePlaylistBody: Data = {
    // See PlaylistDataSourceV1Tests.mojibakeV1Body for the encoding story.
    let json = #"""
    {"playcuts":[{"id":1,"rotation":"false","request":"false","songTitle":"In Your Head","timeCreated":0,"labelName":"ATO Records","hour":0,"artistName":"NilÃ¼fer Yanya","chronOrderID":1,"releaseTitle":"Painless"}],"breakpoints":[],"talksets":[]}
    """#
    return Data(json.utf8)
}()
