//
//  PlaylistServiceCachingTests.swift
//  CoreTests
//
//  Tests for PlaylistService caching functionality including:
//  - Loading cached playlists on initialization
//  - Cache expiration handling
//  - Background refresh always fetching fresh data
//  - Regular fetching caching results
//

import Testing
import Foundation
@testable import Playlist
@testable import Caching

// MARK: - Test Mock Cache

/// Mock cache for PlaylistService caching tests
/// (Defined locally to avoid ambiguity with other MockCache classes)
final class PlaylistServiceMockCache: Cache, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func object(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(object: Data?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let object = object {
            storage[key] = object
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func allRecords() -> any Sequence<(String, Data)> {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.map { ($0.key, $0.value) })
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

// MARK: - Tests

@Suite("PlaylistService Caching Tests")
struct PlaylistServiceCachingTests {
    
    // MARK: - Cache Loading Tests
    
    @Test("Loads cached playlist on initialization if available")
    func loadsCachedPlaylistOnInit() async throws {
        // Given - Set up cache with a playlist
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let cachedPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Cached Song",
                    labelName: nil,
                    artistName: "Cached Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        
        // Cache the playlist
        await cacheCoordinator.set(
            value: cachedPlaylist,
            for: "com.wxyc.playlist.cache",
            lifespan: 15 * 60
        )
        
        // When - Create service (should load from cache)
        let mockFetcher = MockRemotePlaylistFetcher()
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
    
    @Test("Does not load expired cached playlist")
    func doesNotLoadExpiredCache() async throws {
        // Given - Set up cache with expired playlist
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let expiredPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Expired Song",
                    labelName: nil,
                    artistName: "Expired Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        
        // Create an expired record manually
        let expiredRecord = CachedRecord(
            value: expiredPlaylist,
            timestamp: Date.timeIntervalSinceReferenceDate - (16 * 60), // 16 minutes ago
            lifespan: 15 * 60 // 15 minute lifespan
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(expiredRecord)
        mockCache.set(object: encoded, for: "com.wxyc.playlist.cache")
        
        // When - Create service
        let mockFetcher = MockRemotePlaylistFetcher()
        let freshPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 2,
                    hour: 2000,
                    chronOrderID: 2,
                    songTitle: "Fresh Song",
                    labelName: nil,
                    artistName: "Fresh Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = freshPlaylist
        
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
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let cachedPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Cached Song",
                    labelName: nil,
                    artistName: "Cached Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        
        await cacheCoordinator.set(
            value: cachedPlaylist,
            for: "com.wxyc.playlist.cache",
            lifespan: 15 * 60
        )
        
        let mockFetcher = MockRemotePlaylistFetcher()
        let freshPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 2,
                    hour: 2000,
                    chronOrderID: 2,
                    songTitle: "Fresh Song",
                    labelName: nil,
                    artistName: "Fresh Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = freshPlaylist
        
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
        let cached: Playlist = try await cacheCoordinator.value(for: "com.wxyc.playlist.cache")
        #expect(cached.playcuts.first?.songTitle == "Fresh Song")
    }
    
    @Test("fetchAndCachePlaylist updates cache even if playlist unchanged")
    func fetchAndCachePlaylistUpdatesCacheEvenIfUnchanged() async throws {
        // Given
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let mockFetcher = MockRemotePlaylistFetcher()
        let playlist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Same Song",
                    labelName: nil,
                    artistName: "Same Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = playlist
        
        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator
        )
        
        // When - Fetch and cache
        _ = await service.fetchAndCachePlaylist()
        
        // Then - Cache should be updated (timestamp refreshed)
        let cached: Playlist = try await cacheCoordinator.value(for: "com.wxyc.playlist.cache")
        #expect(cached.playcuts.first?.songTitle == "Same Song")
    }
    
    // MARK: - Regular Fetching Caching Tests
    
    @Test("Regular fetching caches results")
    func regularFetchingCachesResults() async throws {
        // Given
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let mockFetcher = MockRemotePlaylistFetcher()
        let playlist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Fetched Song",
                    labelName: nil,
                    artistName: "Fetched Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = playlist
        
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
        let cached: Playlist = try await cacheCoordinator.value(for: "com.wxyc.playlist.cache")
        #expect(cached.playcuts.first?.songTitle == "Fetched Song")
    }
    
    // MARK: - Cache Expiration Tests
    
    @Test("Cache expires after 15 minutes")
    func cacheExpiresAfter15Minutes() async throws {
        // Given - Create a playlist cached 16 minutes ago
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let oldPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Old Song",
                    labelName: nil,
                    artistName: "Old Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        
        // Manually create expired record
        let expiredRecord = CachedRecord(
            value: oldPlaylist,
            timestamp: Date.timeIntervalSinceReferenceDate - (16 * 60), // 16 minutes ago
            lifespan: 15 * 60 // 15 minute lifespan
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(expiredRecord)
        mockCache.set(object: encoded, for: "com.wxyc.playlist.cache")
        
        // When - Try to retrieve
        // Then - Should throw noCachedResult error
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: Playlist = try await cacheCoordinator.value(for: "com.wxyc.playlist.cache")
        }
    }
    
    @Test("Cache is valid within 15 minutes")
    func cacheIsValidWithin15Minutes() async throws {
        // Given - Create a playlist cached 10 minutes ago
        let mockCache = PlaylistServiceMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let recentPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Recent Song",
                    labelName: nil,
                    artistName: "Recent Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        
        // Manually create recent record
        let recentRecord = CachedRecord(
            value: recentPlaylist,
            timestamp: Date.timeIntervalSinceReferenceDate - (10 * 60), // 10 minutes ago
            lifespan: 15 * 60
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(recentRecord)
        mockCache.set(object: encoded, for: "com.wxyc.playlist.cache")
        
        // When - Try to retrieve
        let cached: Playlist = try await cacheCoordinator.value(for: "com.wxyc.playlist.cache")
        
        // Then - Should succeed
        #expect(cached.playcuts.first?.songTitle == "Recent Song")
    }
}

