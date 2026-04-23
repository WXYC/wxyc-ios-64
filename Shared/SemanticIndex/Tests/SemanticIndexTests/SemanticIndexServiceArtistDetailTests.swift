//
//  SemanticIndexServiceArtistDetailTests.swift
//  SemanticIndex
//
//  Tests for SemanticIndexService artist detail and preview fetching.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Core
@testable import Caching
@testable import SemanticIndex

@Suite("SemanticIndexService Artist Detail")
struct SemanticIndexServiceArtistDetailTests {

    @Test("Decodes artist detail with streaming IDs")
    func decodesArtistDetail() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/42"] = """
        {
            "id": 42,
            "canonical_name": "Stereolab",
            "genre": "Rock",
            "total_plays": 500,
            "spotify_artist_id": "sp123",
            "apple_music_artist_id": "am456",
            "bandcamp_id": "stereolab",
            "discogs_artist_id": 99999
        }
        """.data(using: .utf8)!

        let detail = await service.artistDetail(id: 42)

        let result = try #require(detail)
        #expect(result.id == 42)
        #expect(result.canonicalName == "Stereolab")
        #expect(result.spotifyArtistId == "sp123")
        #expect(result.appleMusicArtistId == "am456")
        #expect(result.bandcampId == "stereolab")
        #expect(result.discogsArtistId == 99999)
    }

    @Test("Handles nil streaming IDs gracefully")
    func handlesNilStreamingIDs() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/42"] = """
        {
            "id": 42,
            "canonical_name": "Broadcast",
            "genre": "Electronic",
            "total_plays": 300
        }
        """.data(using: .utf8)!

        let detail = await service.artistDetail(id: 42)

        let result = try #require(detail)
        #expect(result.spotifyArtistId == nil)
        #expect(result.appleMusicArtistId == nil)
        #expect(result.bandcampId == nil)
        #expect(result.discogsArtistId == nil)
    }

    @Test("Returns nil on API error")
    func returnsNilOnError() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        let detail = await service.artistDetail(id: 42)
        #expect(detail == nil)
    }

    @Test("Decodes preview data with artwork and album URL")
    func decodesPreviewData() async throws {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        mockSession.responses["graph/artists/42/preview"] = """
        {
            "preview_url": "https://audio.itunes.apple.com/preview.m4a",
            "track_name": "French Disko",
            "artist_name": "Stereolab",
            "artwork_url": "https://is1.mzstatic.com/image/thumb/Music/artwork.jpg",
            "album_name": "Transient Random-Noise Bursts with Announcements",
            "album_url": "https://music.apple.com/album/transient/123"
        }
        """.data(using: .utf8)!

        let preview = await service.preview(for: 42)

        let result = try #require(preview)
        #expect(result.trackName == "French Disko")
        #expect(result.artistName == "Stereolab")
        #expect(result.albumName == "Transient Random-Noise Bursts with Announcements")
        #expect(result.artworkURL == URL(string: "https://is1.mzstatic.com/image/thumb/Music/artwork.jpg"))
        #expect(result.albumURL == URL(string: "https://music.apple.com/album/transient/123"))
    }

    @Test("Returns nil preview on API error")
    func returnsNilPreviewOnError() async {
        let mockSession = MockWebSession()
        let cache = CacheCoordinator(cache: MockCache())
        let service = SemanticIndexService(
            baseURL: URL(string: "https://explore.wxyc.org")!,
            session: mockSession,
            cache: cache
        )

        let preview = await service.preview(for: 42)
        #expect(preview == nil)
    }
}
