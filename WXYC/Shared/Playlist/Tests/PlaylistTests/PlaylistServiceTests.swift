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
        let playlist1 = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Song 1",
                    labelName: nil,
                    artistName: "Artist 1",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = playlist1

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
        let initialPlaylist = Playlist(
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
        mockFetcher.playlistToReturn = initialPlaylist

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
        let playlist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Fresh Song",
                    labelName: nil,
                    artistName: "Fresh Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = playlist

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

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.05, cacheCoordinator: makeTestCacheCoordinator())

        // When - Get two playlists from stream
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()

        // Update mock to return different playlist for second fetch
        let newPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 2,
                    hour: 2000,
                    chronOrderID: 2,
                    songTitle: "Different Song",
                    labelName: nil,
                    artistName: "Different Artist",
                    releaseTitle: nil
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = newPlaylist

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
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Song 1",
            labelName: nil,
            artistName: "Artist 1",
            releaseTitle: nil
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 2,
            songTitle: "Song 2",
            labelName: nil,
            artistName: "Artist 2",
            releaseTitle: nil
        )

        let playlist1 = Playlist(playcuts: [playcut1], breakpoints: [], talksets: [])
        let playlist2 = Playlist(playcuts: [playcut1], breakpoints: [], talksets: [])
        let playlist3 = Playlist(playcuts: [playcut2], breakpoints: [], talksets: [])

        // Then
        #expect(playlist1 == playlist2)
        #expect(playlist1 != playlist3)
    }

    @Test("Playlist entries are sorted by chronOrderID")
    func playlistEntriesSortedCorrectly() async throws {
        // Given
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 3,
            songTitle: "Song 1",
            labelName: nil,
            artistName: "Artist 1",
            releaseTitle: nil
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 1,
            songTitle: "Song 2",
            labelName: nil,
            artistName: "Artist 2",
            releaseTitle: nil
        )

        let playcut3 = Playcut(
            id: 3,
            hour: 3000,
            chronOrderID: 2,
            songTitle: "Song 3",
            labelName: nil,
            artistName: "Artist 3",
            releaseTitle: nil
        )

        let playlist = Playlist(
            playcuts: [playcut1, playcut2, playcut3],
            breakpoints: [],
            talksets: []
        )

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
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 3,
            songTitle: "Song",
            labelName: nil,
            artistName: "Artist",
            releaseTitle: nil
        )

        let breakpoint = Breakpoint(id: 2, hour: 2000, chronOrderID: 2)
        let talkset = Talkset(id: 3, hour: 3000, chronOrderID: 1)

        let playlist = Playlist(
            playcuts: [playcut],
            breakpoints: [breakpoint],
            talksets: [talkset]
        )

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
        let breakpoint = Breakpoint(
            id: 1,
            hour: millisecondsSince1970,
            chronOrderID: 1
        )

        // When
        let formattedDate = breakpoint.formattedDate

        // Then
        // The exact format will depend on timezone, but it should contain a time
        #expect(!formattedDate.isEmpty)
        #expect(formattedDate.contains("AM") || formattedDate.contains("PM"))
    }
}
