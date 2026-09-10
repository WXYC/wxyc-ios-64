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
            for: PlaylistCacheKey.playlist,
            lifespan: 15 * 60
        )

        // When - Create service (should load from cache)
        let mockFetcher = MockPlaylistFetcher()
        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator
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
        mockCache.set(encoded, metadata: expiredMetadata, for: PlaylistCacheKey.playlist)

        // When - Create service
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 2, hour: 2000, songTitle: "Fresh Song", artistName: "Fresh Artist")
        ])

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.1,
            cacheCoordinator: cacheCoordinator
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
            for: PlaylistCacheKey.playlist,
            lifespan: 15 * 60
        )

        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 2, hour: 2000, songTitle: "Fresh Song", artistName: "Fresh Artist")
        ])

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator
        )

        // When - Call fetchAndCachePlaylist (should ignore cache)
        let fetchedPlaylist = await service.fetchAndCachePlaylist()

        // Then - Should return fresh data
        #expect(fetchedPlaylist.playcuts.first?.songTitle == "Fresh Song")
        #expect(mockFetcher.callCount == 1)
    
        // And - Cache should be updated with fresh data
        let cached: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist)
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
            cacheCoordinator: cacheCoordinator
        )

        // When - Fetch and cache
        _ = await service.fetchAndCachePlaylist()

        // Then - Cache should be updated (timestamp refreshed)
        let cached: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist)
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
            cacheCoordinator: cacheCoordinator
        )

        // When - Start observing (triggers fetch)
        var iterator = service.updates().makeAsyncIterator()
        _ = await iterator.next()

        // Wait for fetch to complete and cache
        try await Task.sleep(for: .milliseconds(150))

        // Then - Cache should contain the fetched playlist
        let cached: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist)
        #expect(cached.playcuts.first?.songTitle == "Fetched Song")
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
        mockCache.set(encoded, metadata: expiredMetadata, for: PlaylistCacheKey.playlist)
    
        // When - Try to retrieve
        // Then - Should throw noCachedResult error
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist)
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
        mockCache.set(encoded, metadata: recentMetadata, for: PlaylistCacheKey.playlist)
        
        // When - Try to retrieve
        let cached: Playlist = try await cacheCoordinator.value(for: PlaylistCacheKey.playlist)

        // Then - Should succeed
        #expect(cached.playcuts.first?.songTitle == "Recent Song")
    }
}
