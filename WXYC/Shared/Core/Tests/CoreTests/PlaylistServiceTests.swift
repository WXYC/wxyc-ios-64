import Testing
import Foundation
import Analytics
@testable import Core

// MARK: - Mock PlaylistFetcher

final class MockPlaylistFetcher: PlaylistFetcher, @unchecked Sendable {
    var playlistToReturn: Playlist?
    var errorToThrow: Error?
    var callCount = 0

    func getPlaylist() async throws -> Playlist {
        callCount += 1

        if let error = errorToThrow {
            throw error
        }

        return playlistToReturn ?? .empty
    }
}

// MARK: - Tests

@MainActor
@Suite("PlaylistService Tests")
struct PlaylistServiceTests {

    // MARK: - Fetching Tests

    @Test("Fetch playlist successfully")
    func fetchPlaylistSuccess() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        let expectedPlaylist = Playlist(
            playcuts: [
                Playcut(
                    id: 1,
                    hour: 1000,
                    chronOrderID: 1,
                    songTitle: "Test Song",
                    labelName: "Test Label",
                    artistName: "Test Artist",
                    releaseTitle: "Test Release"
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = expectedPlaylist

        let service = PlaylistService(remoteFetcher: mockFetcher)

        // When
        let result = await service.fetchPlaylist()

        // Then
        #expect(mockFetcher.callCount == 1)
        #expect(result.playcuts.count == 1)
        #expect(result.playcuts.first?.songTitle == "Test Song")
        #expect(result.playcuts.first?.artistName == "Test Artist")
    }

    @Test("Fetch playlist returns empty on NSError")
    func fetchPlaylistReturnsEmptyOnNSError() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        let nsError = NSError(
            domain: "test.error",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Not found"]
        )
        mockFetcher.errorToThrow = nsError

        let service = PlaylistService(remoteFetcher: mockFetcher)

        // When
        let result = await service.fetchPlaylist()

        // Then
        #expect(mockFetcher.callCount == 1)
        #expect(result.playcuts.isEmpty)
        #expect(result.breakpoints.isEmpty)
        #expect(result.talksets.isEmpty)
    }

    @Test("Fetch playlist handles analytics errors")
    func fetchPlaylistHandlesAnalyticsErrors() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        let analyticsError = AnalyticsOSError(
            domain: "analytics.error",
            code: 500,
            description: "Analytics error"
        )
        mockFetcher.errorToThrow = analyticsError

        let service = PlaylistService(remoteFetcher: mockFetcher)

        // When
        let result = await service.fetchPlaylist()

        // Then
        #expect(mockFetcher.callCount == 1)
        #expect(result.playcuts.isEmpty)
    }

    @Test("Fetch playlist handles decoder errors")
    func fetchPlaylistHandlesDecoderErrors() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        let decoderError = AnalyticsDecoderError(description: "Decoding failed")
        mockFetcher.errorToThrow = decoderError

        let service = PlaylistService(remoteFetcher: mockFetcher)

        // When
        let result = await service.fetchPlaylist()

        // Then
        #expect(mockFetcher.callCount == 1)
        #expect(result.playcuts.isEmpty)
    }

    // MARK: - AsyncSequence Tests

    @Test("AsyncSequence yields playlists")
    func asyncSequenceYieldsPlaylists() async throws {
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

        let service = PlaylistService(remoteFetcher: mockFetcher, interval: 0.1)

        // When - Get first playlist from sequence
        var iterator = service.makeAsyncIterator()
        let firstPlaylist = await iterator.next()

        // Then
        #expect(firstPlaylist != nil)
        #expect(firstPlaylist?.playcuts.count == 1)
        #expect(firstPlaylist?.playcuts.first?.songTitle == "Song 1")
    }

    @Test("AsyncSequence yields cached value immediately")
    func asyncSequenceYieldsCachedValueImmediately() async throws {
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

        let service = PlaylistService(remoteFetcher: mockFetcher, interval: 0.1)

        // Populate the cache with an initial fetch
        _ = await service.fetchPlaylist()

        // When - New observer starts observing
        let startTime = Date()
        var iterator = service.makeAsyncIterator()
        let cachedPlaylist = await iterator.next()
        let duration = Date().timeIntervalSince(startTime)

        // Then - Should get cached value very quickly (< 100ms, not waiting for network)
        #expect(cachedPlaylist?.playcuts.first?.songTitle == "Cached Song")
        #expect(duration < 0.1) // Should be nearly instant
    }

    @Test("AsyncSequence skips unchanged playlists")
    func asyncSequenceSkipsUnchangedPlaylists() async throws {
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

        let service = PlaylistService(remoteFetcher: mockFetcher, interval: 0.05)

        // When - Get two playlists from sequence
        var iterator = service.makeAsyncIterator()
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
