import Testing
import Foundation
import Analytics
@testable import Playlist

// MARK: - Mock PlaylistFetcher

final class MockPlaylistFetcher: PlaylistFetcher, @unchecked Sendable {
    var playlistToReturn: Playlist = .empty
    var errorToThrow: Error?
    var fetchCount = 0

    func getPlaylist() async throws -> Playlist {
        fetchCount += 1

        if let error = errorToThrow {
            throw error
        }

        return playlistToReturn
    }

    func reset() {
        playlistToReturn = .empty
        errorToThrow = nil
        fetchCount = 0
    }
}

// MARK: - RemotePlaylistFetcher Tests

@Suite("RemotePlaylistFetcher Tests")
struct RemotePlaylistFetcherTests {
    @Test("fetchPlaylist returns playlist on success")
    func fetchPlaylistReturnsPlaylistOnSuccess() async {
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
                    releaseTitle: "Test Album"
                )
            ],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = expectedPlaylist

        let fetcher = RemotePlaylistFetcher(remoteFetcher: mockFetcher)
        let result = await fetcher.fetchPlaylist()

        #expect(result == expectedPlaylist)
        #expect(mockFetcher.fetchCount == 1)
    }

    @Test("fetchPlaylist returns empty playlist on NSError")
    func fetchPlaylistReturnsEmptyOnNSError() async {
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.errorToThrow = NSError(domain: "TestDomain", code: 123, userInfo: nil)

        let fetcher = RemotePlaylistFetcher(remoteFetcher: mockFetcher)
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockFetcher.fetchCount == 1)
    }

    @Test("fetchPlaylist returns empty playlist on AnalyticsOSError")
    func fetchPlaylistReturnsEmptyOnAnalyticsOSError() async {
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.errorToThrow = AnalyticsOSError(domain: "TestDomain", code: 123, description: "Test error")

        let fetcher = RemotePlaylistFetcher(remoteFetcher: mockFetcher)
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockFetcher.fetchCount == 1)
    }

    @Test("fetchPlaylist returns empty playlist on AnalyticsDecoderError")
    func fetchPlaylistReturnsEmptyOnAnalyticsDecoderError() async {
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.errorToThrow = AnalyticsDecoderError(description: "Test decoder error")

        let fetcher = RemotePlaylistFetcher(remoteFetcher: mockFetcher)
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockFetcher.fetchCount == 1)
    }

    @Test("fetchPlaylist returns empty playlist on CancellationError")
    func fetchPlaylistReturnsEmptyOnCancellationError() async {
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.errorToThrow = CancellationError()

        let fetcher = RemotePlaylistFetcher(remoteFetcher: mockFetcher)
        let result = await fetcher.fetchPlaylist()

        #expect(result == .empty)
        #expect(mockFetcher.fetchCount == 1)
    }
}
