//
//  PlaycutMetadataServiceCachingTests.swift
//  Metadata
//
//  Tests for PlaycutMetadataService multi-level caching functionality
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import Core
import Playlist
@testable import Caching
@testable import Metadata

// MARK: - Mock Cache

/// Mock cache for PlaycutMetadataService tests (has additional tracking properties)
final class PlaycutMetadataMockCache: Cache, @unchecked Sendable {
    private var dataStorage: [String: Data] = [:]
    private var metadataStorage: [String: CacheMetadata] = [:]
    var getCallCount = 0
    var setCallCount = 0
    var accessedKeys: [String] = []
    var setKeys: [String] = []
    
    func metadata(for key: String) -> CacheMetadata? {
        getCallCount += 1
        accessedKeys.append(key)
        return metadataStorage[key]
    }
    
    func data(for key: String) -> Data? {
        return dataStorage[key]
    }
    
    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        setCallCount += 1
        setKeys.append(key)
        if let data {
            dataStorage[key] = data
            metadataStorage[key] = metadata
        } else {
            remove(for: key)
        }
    }
    
    func remove(for key: String) {
        dataStorage.removeValue(forKey: key)
        metadataStorage.removeValue(forKey: key)
    }
    
    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        metadataStorage.map { ($0.key, $0.value) }
    }

    func clearAll() {
        dataStorage.removeAll()
        metadataStorage.removeAll()
    }

    func totalSize() -> Int64 {
        dataStorage.values.reduce(0) { $0 + Int64($1.count) }
    }

    func reset() {
        getCallCount = 0
        setCallCount = 0
        accessedKeys.removeAll()
        setKeys.removeAll()
    }
}
        
// MARK: - Mock WebSession for Metadata Service
        
final class MetadataMockWebSession: WebSession, @unchecked Sendable {
    var responses: [String: Data] = [:]
    var requestedURLs: [URL] = []
    var requestCount = 0

    func data(from url: URL) async throws -> Data {
        requestCount += 1
        requestedURLs.append(url)
        
        // Return matching response based on URL path
        for (pattern, data) in responses {
            if url.absoluteString.contains(pattern) {
                return data
            }
        }

        throw ServiceError.noResults
    }

    func reset() {
        responses.removeAll()
        requestedURLs.removeAll()
        requestCount = 0
    }
}

// MARK: - Playcut Test Stub

extension Playcut {
    /// Creates a Playcut with sensible defaults for testing.
    static func stub(
        id: UInt64 = 1,
        hour: UInt64 = 1000,
        chronOrderID: UInt64? = nil,
        timeCreated: UInt64? = nil,
        songTitle: String = "Test Song",
        labelName: String? = nil,
        artistName: String = "Test Artist",
        releaseTitle: String? = "Test Album"
    ) -> Playcut {
        Playcut(
            id: id,
            hour: hour,
            chronOrderID: chronOrderID ?? id,
            timeCreated: timeCreated ?? hour,
            songTitle: songTitle,
            labelName: labelName,
            artistName: artistName,
            releaseTitle: releaseTitle
        )
    }
}

// MARK: - PlaycutMetadataService Caching Tests

@Suite("PlaycutMetadataService Caching Tests")
struct PlaycutMetadataServiceCachingTests {

    @Test("Returns cached metadata without making API calls")
    func returnsCachedMetadata() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(id: 12345, labelName: "Test Label")

        // Pre-populate cache with granular metadata
        let albumKey = MetadataCacheKey.album(artistName: "Test Artist", releaseTitle: "Test Album")
        let streamingKey = MetadataCacheKey.streaming(artistName: "Test Artist", songTitle: "Test Song")

        let cachedAlbum = AlbumMetadata(
            label: "Cached Label",
            releaseYear: 2024,
            discogsURL: URL(string: "https://discogs.com/test"),
            discogsArtistId: 999
        )
        let cachedArtist = ArtistMetadata(
            bio: "Cached bio",
            wikipediaURL: nil,
            discogsArtistId: 999
        )
        let cachedStreaming = StreamingLinks(
            spotifyURL: URL(string: "https://spotify.com/test"),
            appleMusicURL: nil,
            youtubeMusicURL: nil,
            bandcampURL: nil,
            soundcloudURL: nil
        )

        await cache.set(value: cachedAlbum, for: albumKey, lifespan: 3600)
        await cache.set(value: cachedArtist, for: MetadataCacheKey.artist(discogsId: 999), lifespan: 3600)
        await cache.set(value: cachedStreaming, for: streamingKey, lifespan: 3600)

        // Reset counters after cache setup
        mockSession.reset()
        mockCache.reset()

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then
        #expect(result.label == "Cached Label")
        #expect(result.releaseYear == 2024)
        #expect(result.artistBio == "Cached bio")
        #expect(result.spotifyURL?.absoluteString == "https://spotify.com/test")
        #expect(mockSession.requestCount == 0, "Should not make any API calls when all metadata is cached")
    }

    @Test("Fetches from API and caches result on cache miss")
    func fetchesAndCachesOnMiss() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            id: 99999,
            songTitle: "New Song",
            labelName: "New Label",
            artistName: "New Artist",
            releaseTitle: "New Album"
        )

        // Mock proxy album metadata response
        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then
        #expect(result.label == "New Label") // Falls back to playcut's label
        #expect(mockCache.setCallCount >= 2, "Should cache album and streaming results")

        // Verify correct cache keys are used
        let albumKey = MetadataCacheKey.album(artistName: "New Artist", releaseTitle: "New Album")
        let streamingKey = MetadataCacheKey.streaming(artistName: "New Artist", songTitle: "New Song")
        #expect(mockCache.setKeys.contains(albumKey), "Should cache album metadata")
        #expect(mockCache.setKeys.contains(streamingKey), "Should cache streaming links")
    }
        
    @Test("Uses correct cache key format for each level")
    func usesCorrectCacheKeys() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(id: 42, artistName: "Artist Name", releaseTitle: "Album Title")

        // Mock proxy response
        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        _ = await service.fetchMetadata(for: playcut)

        // Then - verify granular cache keys
        let expectedAlbumKey = "album-Artist Name-Album Title"
        let expectedStreamingKey = "streaming-Artist Name-Test Song"

        #expect(mockCache.accessedKeys.contains(expectedAlbumKey), "Should check album cache")
        #expect(mockCache.accessedKeys.contains(expectedStreamingKey), "Should check streaming cache")
        #expect(mockCache.setKeys.contains(expectedAlbumKey), "Should set album cache")
        #expect(mockCache.setKeys.contains(expectedStreamingKey), "Should set streaming cache")
    }
        
    @Test("Second fetch returns cached data without API call")
    func secondFetchReturnsCached() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            id: 555,
            songTitle: "Test",
            labelName: "Label",
            artistName: "Artist",
            releaseTitle: "Album"
        )

        // Mock proxy response
        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When - first fetch
        _ = await service.fetchMetadata(for: playcut)
        let firstRequestCount = mockSession.requestCount

        // When - second fetch
        _ = await service.fetchMetadata(for: playcut)
        let secondRequestCount = mockSession.requestCount

        // Then
        #expect(secondRequestCount == firstRequestCount, "Second fetch should not make additional API calls")
    }

    @Test("Parses enriched API response with genres, styles, and fullReleaseDate")
    func parsesEnrichedAPIResponse() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "VI Scose Poise",
            labelName: "Warp",
            artistName: "Autechre",
            releaseTitle: "Confield"
        )

        // Mock enriched album metadata response
        let albumResponse = """
        {
            "discogsReleaseId": 12345,
            "discogsArtistId": 67890,
            "discogsUrl": "https://www.discogs.com/release/12345",
            "releaseYear": 2001,
            "label": "Warp Records",
            "genres": ["Electronic"],
            "styles": ["IDM", "Abstract"],
            "fullReleaseDate": "2001-04-30",
            "spotifyUrl": "https://open.spotify.com/track/abc",
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // Mock artist metadata response
        let artistResponse = """
        {
            "discogsArtistId": 67890,
            "bio": "Autechre are an English electronic music duo.",
            "wikipediaUrl": "https://en.wikipedia.org/wiki/Autechre"
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/artist"] = artistResponse

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then
        #expect(result.album.genres == ["Electronic"])
        #expect(result.album.styles == ["IDM", "Abstract"])
        #expect(result.album.fullReleaseDate == "2001-04-30")
        #expect(result.album.label == "Warp Records")
        #expect(result.album.discogsArtistId == 67890)
        #expect(result.album.releaseYear == 2001)
        #expect(result.artistBio == "Autechre are an English electronic music duo.")
    }

    @Test("Maps discogsArtistId from dedicated field, not discogsReleaseId")
    func mapsDiscogsArtistIdCorrectly() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        )

        // API response where discogsReleaseId != discogsArtistId
        let albumResponse = """
        {
            "discogsReleaseId": 11111,
            "discogsArtistId": 22222,
            "discogsUrl": "https://www.discogs.com/release/11111",
            "releaseYear": 2024,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // Artist response keyed by correct artist ID
        let artistResponse = """
        {
            "discogsArtistId": 22222,
            "bio": "Argentine singer-songwriter.",
            "wikipediaUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/artist"] = artistResponse

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then - discogsArtistId should be 22222 (from dedicated field), NOT 11111 (from releaseId)
        #expect(result.album.discogsArtistId == 22222)
        #expect(result.artistBio == "Argentine singer-songwriter.")
    }

    @Test("Uses API label when available, falls back to playcut label")
    func usesAPILabelOverPlaycutLabel() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        )

        // API response with label field
        let albumResponse = """
        {
            "discogsReleaseId": 99999,
            "discogsUrl": null,
            "releaseYear": 2015,
            "label": "Drag City Records",
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then - should use the API label ("Drag City Records") not the playcut label ("Drag City")
        #expect(result.label == "Drag City Records")
    }

    @Test("Falls back to playcut label when API label is absent")
    func fallsBackToPlaycutLabelWhenAPILabelAbsent() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Moon Pix",
            labelName: "Matador Records",
            artistName: "Cat Power",
            releaseTitle: "Moon Pix"
        )

        // API response without label field
        let albumResponse = """
        {
            "discogsReleaseId": 88888,
            "discogsUrl": null,
            "releaseYear": 1998,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then - should fall back to playcut label
        #expect(result.label == "Matador Records")
    }

    @Test("Enriched fields are nil when absent from API response")
    func enrichedFieldsNilWhenAbsent() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Aluminum Tunes",
            artistName: "Stereolab",
            releaseTitle: "Aluminum Tunes"
        )

        // Minimal API response (old backend format without enriched fields)
        let albumResponse = """
        {
            "discogsReleaseId": 77777,
            "discogsUrl": "https://www.discogs.com/release/77777",
            "releaseYear": 1998,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut)

        // Then - enriched fields should be nil
        #expect(result.album.genres == nil)
        #expect(result.album.styles == nil)
        #expect(result.album.fullReleaseDate == nil)
    }

    @Test("Same artist across different songs shares cached artist metadata")
    func sameArtistSharesCachedMetadata() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        // Pre-populate artist cache
        let artistMetadata = ArtistMetadata(
            bio: "Shared artist bio",
            wikipediaURL: URL(string: "https://wikipedia.org/artist"),
            discogsArtistId: 12345
        )
        await cache.set(value: artistMetadata, for: MetadataCacheKey.artist(discogsId: 12345), lifespan: .thirtyDays)

        // Two different songs by the same artist
        let song1 = Playcut.stub(songTitle: "Song 1", artistName: "Same Artist", releaseTitle: "Album A")
        let song2 = Playcut.stub(id: 2, hour: 1001, songTitle: "Song 2", artistName: "Same Artist", releaseTitle: "Album B")

        // Pre-populate album caches with same artist ID
        let album1 = AlbumMetadata(label: "Label A", releaseYear: 2020, discogsURL: nil, discogsArtistId: 12345)
        let album2 = AlbumMetadata(label: "Label B", releaseYear: 2021, discogsURL: nil, discogsArtistId: 12345)
        await cache.set(value: album1, for: MetadataCacheKey.album(artistName: "Same Artist", releaseTitle: "Album A"), lifespan: .sevenDays)
        await cache.set(value: album2, for: MetadataCacheKey.album(artistName: "Same Artist", releaseTitle: "Album B"), lifespan: .sevenDays)

        // Pre-populate streaming caches
        let streaming1 = StreamingLinks(spotifyURL: URL(string: "https://spotify.com/1"))
        let streaming2 = StreamingLinks(spotifyURL: URL(string: "https://spotify.com/2"))
        await cache.set(value: streaming1, for: MetadataCacheKey.streaming(artistName: "Same Artist", songTitle: "Song 1"), lifespan: .sevenDays)
        await cache.set(value: streaming2, for: MetadataCacheKey.streaming(artistName: "Same Artist", songTitle: "Song 2"), lifespan: .sevenDays)

        mockCache.reset()
        mockSession.reset()

        // When
        let result1 = await service.fetchMetadata(for: song1)
        let result2 = await service.fetchMetadata(for: song2)

        // Then - both should have the same artist bio
        #expect(result1.artistBio == "Shared artist bio")
        #expect(result2.artistBio == "Shared artist bio")
        #expect(result1.label == "Label A")
        #expect(result2.label == "Label B")
        #expect(mockSession.requestCount == 0, "No API calls needed when all cached")
    }
}
