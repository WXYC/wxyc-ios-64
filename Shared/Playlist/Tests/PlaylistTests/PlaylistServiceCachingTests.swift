//
//  PlaylistServiceCachingTests.swift
//  Playlist
//
//  Tests for PlaylistService caching functionality including:
//  - Loading cached playlists on initialization
//  - Cache expiration handling
//  - Background refresh always fetching fresh data
//  - Regular fetching caching results
//
//  Created by Jake Bromberg on 12/04/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import PlaylistTesting
@testable import Playlist
@testable import Caching

// MARK: - Tests

@Suite("PlaylistService Caching Tests")
struct PlaylistServiceCachingTests {

    // MARK: - Cache Loading Tests
    
    @Test("Loads cached playlist on initialization if available", .timeLimit(.minutes(1)))
    func loadsCachedPlaylistOnInit() async throws {
        // Given - Set up cache with a playlist
        let mockCache = InMemoryCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let cachedPlaylist = Playlist.stub(playcuts: [.stub(songTitle: "Cached Song", artistName: "Cached Artist")])

        // Cache the playlist
        await cacheCoordinator.set(
            value: cachedPlaylist,
            for: PlaylistCacheKey.playlist(for: .v1),
            lifespan: 15 * 60
        )

        // When - Create service (should load from cache)
        let mockFetcher = MockPlaylistFetcher()
        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // Wait a bit for async cache loading
        try await Task.sleep(for: .milliseconds(100))

        // Then - Should yield cached playlist immediately
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()

        #expect(firstPlaylist?.playcuts.first?.songTitle == "Cached Song")
        // Note: fetcher may have been called by the time we check, so we just verify we got cached data
    }

    @Test("Does not load expired cached playlist", .timeLimit(.minutes(1)))
    func doesNotLoadExpiredCache() async throws {
        // Given - Set up cache with expired playlist
        let mockCache = InMemoryCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let expiredPlaylist = Playlist.stub(playcuts: [.stub(songTitle: "Expired Song", artistName: "Expired Artist")])

        // Create an expired record manually
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(expiredPlaylist)
        let expiredMetadata = CacheMetadata(
            timestamp: Date.timeIntervalSinceReferenceDate - (16 * 60), // 16 minutes ago
            lifespan: 15 * 60 // 15 minute lifespan
        )
        mockCache.set(encoded, metadata: expiredMetadata, for: PlaylistCacheKey.playlist(for: .v1))

        // When - Create service
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 2, hour: 2000, songTitle: "Fresh Song", artistName: "Fresh Artist")
        ])

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.1,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // Wait for initial load attempt
        try await Task.sleep(for: .milliseconds(100))

        // Then - Should fetch fresh data, not use expired cache
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()
        
        #expect(firstPlaylist?.playcuts.first?.songTitle == "Fresh Song")
        #expect(firstPlaylist?.playcuts.first?.songTitle != "Expired Song")
    }

    // MARK: - fetchAndCachePlaylist Tests

    @Test("fetchAndCachePlaylist always fetches fresh data")
    func fetchAndCachePlaylistAlwaysFetchesFresh() async throws {
        // Given - Set up service with cached data
        let mockCache = InMemoryCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let cachedPlaylist = Playlist.stub(playcuts: [.stub(songTitle: "Cached Song", artistName: "Cached Artist")])

        await cacheCoordinator.set(
            value: cachedPlaylist,
            for: PlaylistCacheKey.playlist(for: .v1),
            lifespan: 15 * 60
        )

        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 2, hour: 2000, songTitle: "Fresh Song", artistName: "Fresh Artist")
        ])

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - Call fetchAndCachePlaylist (should ignore cache)
        let fetchedPlaylist = await service.fetchAndCachePlaylist()

        // Then - Should return fresh data
        #expect(fetchedPlaylist.playcuts.first?.songTitle == "Fresh Song")
        #expect(mockFetcher.callCount == 1)
    
        // And - Cache should be updated with fresh data
        let cached: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist(for: .v1))
        #expect(cached.playcuts.first?.songTitle == "Fresh Song")
    }

    @Test("fetchAndCachePlaylist updates cache even if playlist unchanged")
    func fetchAndCachePlaylistUpdatesCacheEvenIfUnchanged() async throws {
        // Given
        let mockCache = InMemoryCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Same Song", artistName: "Same Artist")])

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - Fetch and cache
        _ = await service.fetchAndCachePlaylist()

        // Then - Cache should be updated (timestamp refreshed)
        let cached: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist(for: .v1))
        #expect(cached.playcuts.first?.songTitle == "Same Song")
    }

    // MARK: - Regular Fetching Caching Tests

    @Test("Regular fetching caches results", .timeLimit(.minutes(1)))
    func regularFetchingCachesResults() async throws {
        // Given
        let mockCache = InMemoryCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Fetched Song", artistName: "Fetched Artist")])
        
        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.1,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - Start observing (triggers fetch)
        var iterator = service.updates().makeAsyncIterator()
        _ = await iterator.next()

        // Wait for fetch to complete and cache
        try await Task.sleep(for: .milliseconds(150))

        // Then - Cache should contain the fetched playlist
        let cached: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist(for: .v1))
        #expect(cached.playcuts.first?.songTitle == "Fetched Song")
    }
        
    // MARK: - Per-version cache isolation (#839 review)

    @Test("A cache written by a v1 session is never served to a v2 session", .timeLimit(.minutes(1)))
    func versionsDoNotShareCacheEntries() async throws {
        // The two versions write chronOrderIDs nine orders of magnitude apart.
        // A v1 session (flag miss, offline launch, DebugPanel switch, the
        // widget process) that seeded a shared entry would hand the next v2
        // launch id-scale rows as its SSE baseline; the first live-fs update
        // frame would then give one stale row a packed key and the head of
        // every now-playing surface.
        let mockCache = InMemoryCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)

        let v1Fetcher = MockPlaylistFetcher()
        v1Fetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 5_306_408, chronOrderID: 5_306_408, songTitle: "v1 Song")
        ])
        let v1Service = PlaylistService(
            fetcher: v1Fetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )
        _ = await v1Service.fetchAndCachePlaylist()

        // fetchPlaylist prefers a live cache entry over the network, so a
        // shared key would return the v1 rows here without touching the
        // fetcher.
        let v2Fetcher = MockPlaylistFetcher()
        v2Fetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 5_306_409, chronOrderID: UInt64(42) << 32 | 1, songTitle: "v2 Song")
        ])
        let v2Service = PlaylistService(
            fetcher: v2Fetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v2
        )
        let playlist = await v2Service.fetchPlaylist()

        #expect(playlist.playcuts.first?.songTitle == "v2 Song")
        #expect(v2Fetcher.callCount == 1)
    }

    // MARK: - Cache Expiration Tests

    @Test("Cache expires after 15 minutes")
    func cacheExpiresAfter15Minutes() async throws {
        // Given - Create a playlist cached 16 minutes ago
        let mockCache = InMemoryCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let oldPlaylist = Playlist.stub(playcuts: [.stub(songTitle: "Old Song", artistName: "Old Artist")])
        
        // Manually create expired record
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(oldPlaylist)
        let expiredMetadata = CacheMetadata(
            timestamp: Date.timeIntervalSinceReferenceDate - (16 * 60), // 16 minutes ago
            lifespan: 15 * 60 // 15 minute lifespan
        )
        mockCache.set(encoded, metadata: expiredMetadata, for: PlaylistCacheKey.playlist(for: .v1))
    
        // When - Try to retrieve
        // Then - Should throw noCachedResult error
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist(for: .v1))
        }
    }

    @Test("Cache is valid within 15 minutes")
    func cacheIsValidWithin15Minutes() async throws {
        // Given - Create a playlist cached 10 minutes ago
        let mockCache = InMemoryCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let recentPlaylist = Playlist.stub(playcuts: [.stub(songTitle: "Recent Song", artistName: "Recent Artist")])

        // Manually create recent record
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(recentPlaylist)
        let recentMetadata = CacheMetadata(
            timestamp: Date.timeIntervalSinceReferenceDate - (10 * 60), // 10 minutes ago
            lifespan: 15 * 60
        )
        mockCache.set(encoded, metadata: recentMetadata, for: PlaylistCacheKey.playlist(for: .v1))
        
        // When - Try to retrieve
        let cached: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist(for: .v1))

        // Then - Should succeed
        #expect(cached.playcuts.first?.songTitle == "Recent Song")
    }
}
