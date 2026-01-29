//
//  PlaylistServiceBackgroundRefreshTests.swift
//  Playlist
//
//  Tests for PlaylistService background refresh functionality:
//  - fetchAndCachePlaylist always fetches fresh data (ignores cache)
//  - Background refresh invalidates existing cache
//
//  Created by Jake Bromberg on 12/04/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
@testable import Caching

// PlaylistServiceMockCache is defined in PlaylistServiceCachingTests.swift

@Suite("PlaylistService Background Refresh Tests")
struct PlaylistServiceBackgroundRefreshTests {
    
    @Test("fetchAndCachePlaylist invalidates existing cache")
    func fetchAndCachePlaylistInvalidatesExistingCache() async throws {
        // Given - Service with cached data
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let oldPlaylist = Playlist.stub(playcuts: [
            .stub(songTitle: "Old Song", artistName: "Old Artist", releaseTitle: nil)
        ])

        await cacheCoordinator.set(
            value: oldPlaylist,
            for: "com.wxyc.playlist.cache",
            lifespan: 15 * 60
        )

        let mockFetcher = MockPlaylistFetcher()
        let newPlaylist = Playlist.stub(playcuts: [
            .stub(id: 2, hour: 2000, songTitle: "New Song", artistName: "New Artist", releaseTitle: nil)
        ])
        mockFetcher.playlistToReturn = newPlaylist
        
        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator
        )
        
        // When - Background refresh fetches (should ignore cache)
        let fetched = await service.fetchAndCachePlaylist()
        
        // Then - Cache should be updated with new data
        let cached: Playlist = try await cacheCoordinator.value(for: "com.wxyc.playlist.cache")
        #expect(cached.playcuts.first?.songTitle == "New Song")
        #expect(cached.playcuts.first?.songTitle != "Old Song")
        #expect(fetched.playcuts.first?.songTitle == "New Song")
    }
    
    @Test("fetchAndCachePlaylist always calls fetcher even with valid cache")
    func fetchAndCachePlaylistAlwaysCallsFetcher() async throws {
        // Given - Valid cached data
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let cachedPlaylist = Playlist.stub(playcuts: [
            .stub(songTitle: "Cached", artistName: "Artist", releaseTitle: nil)
        ])

        await cacheCoordinator.set(
            value: cachedPlaylist,
            for: "com.wxyc.playlist.cache",
            lifespan: 15 * 60
        )

        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = cachedPlaylist // Same data, but should still fetch
        
        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator
        )
    
        // When - Background refresh
        _ = await service.fetchAndCachePlaylist()
        
        // Then - Fetcher should have been called
        #expect(mockFetcher.callCount == 1)
    }
}
