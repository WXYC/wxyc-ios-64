//
//  PlaylistServiceTests.swift
//  Playlist
//
//  Tests for PlaylistService subscription behavior.
//
//  Created by Jake Bromberg on 11/10/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
@testable import Caching

// MARK: - Mock PlaylistFetcher

final class MockPlaylistFetcher: PlaylistFetcherProtocol, @unchecked Sendable {
    var playlistToReturn: Playlist = .empty
    var callCount = 0

    func fetchPlaylist() async -> Playlist {
        callCount += 1
        return playlistToReturn
    }
}

// MARK: - Mock Cache for Tests

/// In-memory cache for isolated test execution
final class PlaylistTestMockCache: Cache, @unchecked Sendable {
    private var dataStorage: [String: Data] = [:]
    private var metadataStorage: [String: CacheMetadata] = [:]
    private let lock = NSLock()

    func metadata(for key: String) -> CacheMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return metadataStorage[key]
    }
    
    func data(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return dataStorage[key]
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data = data {
            dataStorage[key] = data
            metadataStorage[key] = metadata
        } else {
            remove(for: key)
        }
    }
    
    func remove(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        dataStorage.removeValue(forKey: key)
        metadataStorage.removeValue(forKey: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        lock.lock()
        defer { lock.unlock() }
        return metadataStorage.map { ($0.key, $0.value) }
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        dataStorage.removeAll()
        metadataStorage.removeAll()
    }

    func totalSize() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return dataStorage.values.reduce(0) { $0 + Int64($1.count) }
    }
}

/// Helper to create an isolated cache coordinator for testing
func makeTestCacheCoordinator() -> CacheCoordinator {
    CacheCoordinator(cache: PlaylistTestMockCache())
}

// MARK: - Tests

@MainActor
@Suite("PlaylistService Tests", .serialized)
struct PlaylistServiceTests {

    // MARK: - Updates Stream Tests

    @Test("Updates stream yields playlists", .timeLimit(.minutes(1)))
    func updatesStreamYieldsPlaylists() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Song 1", artistName: "Artist 1")])

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.1, cacheCoordinator: makeTestCacheCoordinator())

        // When - Get first playlist from stream (waits for fetch since cache is empty)
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()

        // Then
        #expect(firstPlaylist != nil)
        #expect(firstPlaylist?.playcuts.count == 1)
        #expect(firstPlaylist?.playcuts.first?.songTitle == "Song 1")
    }

    @Test("Updates stream yields cached value immediately", .timeLimit(.minutes(1)))
    func updatesStreamYieldsCachedValueImmediately() async throws {
        // Given - Set up service with initial data
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Cached Song", artistName: "Cached Artist")])

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.1, cacheCoordinator: makeTestCacheCoordinator())

        // Populate the cache with an initial fetch from the first observer
        var firstIterator = service.updates().makeAsyncIterator()
        _ = await firstIterator.next()

        // When - New observer starts observing (should get cached value immediately)
        let startTime = Date()
        var secondIterator = service.updates().makeAsyncIterator()
        let cachedPlaylist = await secondIterator.next()
        let duration = Date().timeIntervalSince(startTime)

        // Then - Should get cached value very quickly (< 100ms, not waiting for network)
        #expect(cachedPlaylist?.playcuts.first?.songTitle == "Cached Song")
        #expect(duration < 0.1) // Should be nearly instant
    }

    @Test("Updates stream waits for first fetch when cache is empty", .timeLimit(.minutes(1)))
    func updatesStreamWaitsForFirstFetchWhenCacheIsEmpty() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Fresh Song", artistName: "Fresh Artist")])

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.1, cacheCoordinator: makeTestCacheCoordinator())

        // When - Observer starts with empty cache
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()

        // Then - Should get the fetched playlist (not empty)
        #expect(firstPlaylist?.playcuts.first?.songTitle == "Fresh Song")
        #expect(mockFetcher.callCount == 1)
    }

    @Test("Updates stream only broadcasts when playlist changes", .timeLimit(.minutes(1)))
    func updatesStreamOnlyBroadcastsWhenPlaylistChanges() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Same Song", artistName: "Same Artist")])

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.05, cacheCoordinator: makeTestCacheCoordinator())

        // When - Get two playlists from stream
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()

        // Update mock to return different playlist for second fetch
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 2, hour: 2000, songTitle: "Different Song", artistName: "Different Artist")
        ])

        let secondPlaylist = await iterator.next()

        // Then
        #expect(firstPlaylist?.playcuts.first?.songTitle == "Same Song")
        #expect(secondPlaylist?.playcuts.first?.songTitle == "Different Song")
        #expect(mockFetcher.callCount >= 2)
    }

    // MARK: - Playlist Comparison Tests

    @Test("Playlist equality works correctly")
    func playlistEquality() async throws {
        // Given
        let playcut1 = Playcut.stub(songTitle: "Song 1", artistName: "Artist 1")
        let playcut2 = Playcut.stub(id: 2, hour: 2000, songTitle: "Song 2", artistName: "Artist 2")

        let playlist1 = Playlist.stub(playcuts: [playcut1])
        let playlist2 = Playlist.stub(playcuts: [playcut1])
        let playlist3 = Playlist.stub(playcuts: [playcut2])

        // Then
        #expect(playlist1 == playlist2)
        #expect(playlist1 != playlist3)
    }

    @Test("Playlist entries are sorted by chronOrderID")
    func playlistEntriesSortedCorrectly() async throws {
        // Given
        let playcut1 = Playcut.stub(id: 1, hour: 1000, chronOrderID: 3, songTitle: "Song 1", artistName: "Artist 1")
        let playcut2 = Playcut.stub(id: 2, hour: 2000, chronOrderID: 1, songTitle: "Song 2", artistName: "Artist 2")
        let playcut3 = Playcut.stub(id: 3, hour: 3000, chronOrderID: 2, songTitle: "Song 3", artistName: "Artist 3")

        let playlist = Playlist.stub(playcuts: [playcut1, playcut2, playcut3])

        // When
        let entries = playlist.entries

        // Then
        #expect(entries.count == 3)
        #expect(entries[0].chronOrderID == 3) // Sorted descending
        #expect(entries[1].chronOrderID == 2)
        #expect(entries[2].chronOrderID == 1)
    }

    @Test("Empty playlist has no entries")
    func emptyPlaylistHasNoEntries() async throws {
        // Given
        let playlist = Playlist.empty

        // Then
        #expect(playlist.playcuts.isEmpty)
        #expect(playlist.breakpoints.isEmpty)
        #expect(playlist.talksets.isEmpty)
        #expect(playlist.entries.isEmpty)
    }

    // MARK: - Mixed Entry Types Tests

    @Test("Playlist with mixed entry types")
    func playlistWithMixedEntryTypes() async throws {
        // Given
        let playcut = Playcut.stub(id: 1, hour: 1000, chronOrderID: 3, songTitle: "Song", artistName: "Artist")
        let breakpoint = Breakpoint.stub(id: 2, hour: 2000, chronOrderID: 2)
        let talkset = Talkset.stub(id: 3, hour: 3000, chronOrderID: 1)

        let playlist = Playlist.stub(playcuts: [playcut], breakpoints: [breakpoint], talksets: [talkset])

        // When
        let entries = playlist.entries

        // Then
        #expect(entries.count == 3)

        // Check that entries are sorted correctly (descending by chronOrderID)
        #expect(entries[0].id == 1) // playcut with chronOrderID 3
        #expect(entries[1].id == 2) // breakpoint with chronOrderID 2
        #expect(entries[2].id == 3) // talkset with chronOrderID 1

        // Check entry types
        #expect(entries[0] is Playcut)
        #expect(entries[1] is Breakpoint)
        #expect(entries[2] is Talkset)
    }

    // MARK: - Breakpoint Tests

    @Test("Breakpoint formats date correctly")
    func breakpointFormatsDate() async throws {
        // Given - Using a known timestamp: January 1, 2020 at 3:00 PM UTC
        let millisecondsSince1970: UInt64 = 1577890800000 // Wed Jan 01 2020 15:00:00 GMT+0000
        let breakpoint = Breakpoint.stub(hour: millisecondsSince1970, timeCreated: millisecondsSince1970)

        // When
        let formattedDate = breakpoint.formattedDate

        // Then
        // The exact format will depend on timezone, but it should contain a time
        #expect(!formattedDate.isEmpty)
        #expect(formattedDate.contains("AM") || formattedDate.contains("PM"))
    }

    // MARK: - Empty Playlist Protection Tests

    @Test("Empty playlist from fetch does not replace valid data", .timeLimit(.minutes(1)))
    func emptyPlaylistDoesNotReplaceValidData() async {
        // Given - A service with valid cached data
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Valid Song", artistName: "Valid Artist")])

        let service = PlaylistService(fetcher: mockFetcher, interval: 30, cacheCoordinator: makeTestCacheCoordinator())

        // First, establish valid data
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()
        #expect(firstPlaylist?.playcuts.first?.songTitle == "Valid Song")

        // When - Fetcher starts returning empty (simulating network error)
        mockFetcher.playlistToReturn = .empty

        // Force a fetch that returns empty
        _ = await service.fetchAndCachePlaylist()

        // Then - Service should still have the valid data (not replaced by empty)
        // Verify by subscribing again - should get the cached valid data
        var newIterator = service.updates().makeAsyncIterator()
        let cachedPlaylist = await newIterator.next()
        #expect(cachedPlaylist?.playcuts.first?.songTitle == "Valid Song")
    }

    @Test("fetchAndCachePlaylist does not replace valid data with empty", .timeLimit(.minutes(1)))
    func fetchAndCachePlaylistDoesNotReplaceValidDataWithEmpty() async throws {
        // Given - A service with valid cached data
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Valid Song", artistName: "Valid Artist")])

        let service = PlaylistService(fetcher: mockFetcher, interval: 30, cacheCoordinator: makeTestCacheCoordinator())

        // First, establish valid data via fetchAndCachePlaylist
        _ = await service.fetchAndCachePlaylist()

        // When - Fetcher starts returning empty (simulating network error)
        mockFetcher.playlistToReturn = .empty
        let emptyResult = await service.fetchAndCachePlaylist()

        // Then - The returned value is empty (as fetched)
        #expect(emptyResult == .empty)

        // But the cached/in-memory data should still be valid
        var iterator = service.updates().makeAsyncIterator()
        let cachedPlaylist = await iterator.next()
        #expect(cachedPlaylist?.playcuts.first?.songTitle == "Valid Song")
    }

    @Test("Empty playlist is accepted when no valid data exists", .timeLimit(.minutes(1)))
    func emptyPlaylistAcceptedWhenNoValidDataExists() async throws {
        // Given - A service with no data
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .empty

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.05, cacheCoordinator: makeTestCacheCoordinator())

        // When - First fetch returns empty
        var iterator = service.updates().makeAsyncIterator()

        // The iterator will wait for data, but since empty is the only thing available
        // and we have no prior data, it should eventually yield empty
        let result = await service.fetchAndCachePlaylist()

        // Then - Empty should be accepted since we have no prior data
        #expect(result == .empty)
    }

    // MARK: - Cache Expiration Tests

    @Test("isCacheExpired returns true when cache is empty", .timeLimit(.minutes(1)))
    func isCacheExpiredReturnsTrueWhenEmpty() async {
        // Given - A service with no cached data
        let mockFetcher = MockPlaylistFetcher()
        let service = PlaylistService(fetcher: mockFetcher, interval: 30, cacheCoordinator: makeTestCacheCoordinator())

        // Wait for initial cache load to complete
        await service.waitForCacheLoad()

        // When
        let isExpired = await service.isCacheExpired()

        // Then
        #expect(isExpired == true)
    }

    @Test("isCacheExpired returns false when cache is valid", .timeLimit(.minutes(1)))
    func isCacheExpiredReturnsFalseWhenValid() async throws {
        // Given - A service with cached data
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(songTitle: "Cached Song", artistName: "Cached Artist")])

        let service = PlaylistService(fetcher: mockFetcher, interval: 30, cacheCoordinator: makeTestCacheCoordinator())

        // Populate cache
        _ = await service.fetchAndCachePlaylist()

        // When
        let isExpired = await service.isCacheExpired()

        // Then
        #expect(isExpired == false)
    }

    // MARK: - Cache Load Race Condition Tests

    @Test("Observer receives cached data even if subscription happens during cache load", .timeLimit(.minutes(1)))
    func observerReceivesCachedDataDuringCacheLoad() async throws {
        // Given - Pre-populate cache before creating service
        let mockCache = PlaylistTestMockCache()
        let cacheCoordinator = CacheCoordinator(cache: mockCache)
        let cachedPlaylist = Playlist.stub(playcuts: [.stub(songTitle: "Pre-cached Song", artistName: "Pre-cached Artist")])

        // Pre-populate the cache
        await cacheCoordinator.set(
            value: cachedPlaylist,
            for: "com.wxyc.playlist.cache",
            lifespan: 15 * 60
        )

        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = cachedPlaylist

        // When - Create service (cache load starts) and immediately subscribe
        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator
        )

        // Subscribe immediately (before cache load might complete)
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()
    
        // Then - Should receive the cached data (not empty, and not have to wait for network)
        #expect(firstPlaylist?.playcuts.first?.songTitle == "Pre-cached Song")
    }
}
