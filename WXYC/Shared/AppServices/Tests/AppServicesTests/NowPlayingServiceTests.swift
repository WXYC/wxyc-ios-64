import Testing
import Foundation
import Artwork
@testable import Playlist
@testable import AppServices

// MARK: - Mock Types

final class MockRemotePlaylistFetcher: RemotePlaylistFetcher, @unchecked Sendable {
    var playlistToReturn: Playlist = .empty
    var callCount = 0

    override func fetchPlaylist() async -> Playlist {
        callCount += 1
        return playlistToReturn
    }
}

final class MockArtworkService: ArtworkService, @unchecked Sendable {
    var artworkToReturn: Image?
    var errorToThrow: Error?
    var fetchCount = 0
    var delaySeconds: Double = 0
    var lastPlaycut: Playcut?

    func fetchArtwork(for playcut: Playcut) async throws -> Image {
        fetchCount += 1
        lastPlaycut = playcut

        if delaySeconds > 0 {
            try? await Task.sleep(for: .seconds(delaySeconds))
        }

        if let error = errorToThrow {
            throw error
        }

        guard let artwork = artworkToReturn else {
            throw ArtworkServiceError.noResults
        }

        return artwork
    }
}

enum ArtworkServiceError: Error {
    case noResults
}

// MARK: - Tests

@MainActor
@Suite("NowPlayingService Tests")
struct NowPlayingServiceTests {

    // MARK: - AsyncSequence Tests

    @Test("AsyncSequence yields NowPlayingItem from playlist")
    func asyncSequenceYieldsNowPlayingItem() async throws {
        // Given
        let mockFetcher = MockRemotePlaylistFetcher()
        let mockArtworkService = MockArtworkService()
        let testImage = Image.gradientImage()
        mockArtworkService.artworkToReturn = testImage

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: nil
        )
        let playlist = Playlist(
            playcuts: [playcut],
            breakpoints: [],
            talksets: []
        )
        mockFetcher.playlistToReturn = playlist

        let playlistService = PlaylistService(fetcher: mockFetcher, interval: 0.1)
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: mockArtworkService
        )

        // When - Get first item from sequence
        var iterator = nowPlayingService.makeAsyncIterator()
        let nowPlayingItem = try await iterator.next()

        // Then
        #expect(nowPlayingItem != nil)
        #expect(nowPlayingItem?.playcut.songTitle == "Test Song")
        #expect(nowPlayingItem?.playcut.artistName == "Test Artist")
        #expect(nowPlayingItem?.artwork === testImage)
        let artworkCallCount = mockArtworkService.fetchCount
        #expect(artworkCallCount == 1)
    }

    @Test("AsyncSequence skips empty playlists")
    func asyncSequenceSkipsEmptyPlaylists() async throws {
        // Given
        let mockFetcher = MockRemotePlaylistFetcher()
        let mockArtworkService = MockArtworkService()

        // Start with empty playlist
        mockFetcher.playlistToReturn = .empty

        let playlistService = PlaylistService(fetcher: mockFetcher, interval: 0.05)
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: mockArtworkService
        )

        var iterator = nowPlayingService.makeAsyncIterator()

        // When - Update to have a playcut after iterator is created
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            let playcut = Playcut(
                id: 1,
                hour: 1000,
                chronOrderID: 1,
                songTitle: "Test Song",
                labelName: nil,
                artistName: "Test Artist",
                releaseTitle: nil
            )
            mockFetcher.playlistToReturn = Playlist(
                playcuts: [playcut],
                breakpoints: [],
                talksets: []
            )
        }

        let nowPlayingItem = try await iterator.next()

        // Then - Should skip empty and get the first valid one
        #expect(nowPlayingItem != nil)
        #expect(nowPlayingItem?.playcut.songTitle == "Test Song")
    }

    @Test("AsyncSequence updates when playlist changes")
    func asyncSequenceUpdatesWhenPlaylistChanges() async throws {
        // Given
        let mockFetcher = MockRemotePlaylistFetcher()
        let mockArtworkService = MockArtworkService()

        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "First Song",
            labelName: nil,
            artistName: "First Artist",
            releaseTitle: nil
        )
        mockFetcher.playlistToReturn = Playlist(
            playcuts: [playcut1],
            breakpoints: [],
            talksets: []
        )

        let playlistService = PlaylistService(fetcher: mockFetcher, interval: 0.05)
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: mockArtworkService
        )

        var iterator = nowPlayingService.makeAsyncIterator()

        // When - Get first item
        let firstItem = try await iterator.next()

        // Then
        #expect(firstItem?.playcut.songTitle == "First Song")

        // When - Update playlist with new playcut
        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 2,
            songTitle: "Second Song",
            labelName: nil,
            artistName: "Second Artist",
            releaseTitle: nil
        )
        mockFetcher.playlistToReturn = Playlist(
            playcuts: [playcut2],
            breakpoints: [],
            talksets: []
        )

        let secondItem = try await iterator.next()

        // Then
        #expect(secondItem?.playcut.songTitle == "Second Song")
        #expect(secondItem?.playcut.artistName == "Second Artist")
    }

    @Test("AsyncSequence uses first playcut from playlist")
    func asyncSequenceUsesFirstPlaycut() async throws {
        // Given
        let mockFetcher = MockRemotePlaylistFetcher()
        let mockArtworkService = MockArtworkService()

        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 3,
            songTitle: "Third Song",
            labelName: nil,
            artistName: "Artist 3",
            releaseTitle: nil
        )
        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 2,
            songTitle: "Second Song",
            labelName: nil,
            artistName: "Artist 2",
            releaseTitle: nil
        )
        let playcut3 = Playcut(
            id: 3,
            hour: 3000,
            chronOrderID: 1,
            songTitle: "First Song",
            labelName: nil,
            artistName: "Artist 1",
            releaseTitle: nil
        )

        // Playlist with multiple playcuts (sorted descending by chronOrderID)
        mockFetcher.playlistToReturn = Playlist(
            playcuts: [playcut1, playcut2, playcut3],
            breakpoints: [],
            talksets: []
        )

        let playlistService = PlaylistService(fetcher: mockFetcher, interval: 0.1)
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: mockArtworkService
        )

        // When
        var iterator = nowPlayingService.makeAsyncIterator()
        let nowPlayingItem = try await iterator.next()

        // Then - Should use the first playcut (highest chronOrderID)
        #expect(nowPlayingItem?.playcut.id == 1)
        #expect(nowPlayingItem?.playcut.songTitle == "Third Song")
        #expect(nowPlayingItem?.playcut.chronOrderID == 3)
    }

    // MARK: - NowPlayingItem Tests

    @Test("NowPlayingItem equality works correctly")
    func nowPlayingItemEquality() async throws {
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

        let item1 = NowPlayingItem(playcut: playcut1, artwork: nil)
        let item2 = NowPlayingItem(playcut: playcut1, artwork: nil)
        let item3 = NowPlayingItem(playcut: playcut2, artwork: nil)

        // Then
        #expect(item1 == item2)
        #expect(item1 != item3)
    }

    @Test("NowPlayingItem comparison by chronOrderID")
    func nowPlayingItemComparison() async throws {
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

        let item1 = NowPlayingItem(playcut: playcut1, artwork: nil)
        let item2 = NowPlayingItem(playcut: playcut2, artwork: nil)

        // Then
        #expect(item1 < item2)
        #expect(!(item2 < item1))
    }
}

// MARK: - Helper Extensions


#if canImport(UIKit)
import UIKit

extension Image {
    /// Creates a gradient image with the specified size and colors
    static func gradientImage(
        size: CGSize = CGSize(width: 200, height: 200),
        colors: [UIColor] = [.systemBlue, .systemPurple],
        startPoint: CGPoint = CGPoint(x: 0, y: 0),
        endPoint: CGPoint = CGPoint(x: 1, y: 1)
    ) -> Image {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Create gradient
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let cgColors = colors.map { $0.cgColor } as CFArray
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: nil) else {
                return
            }
            
            // Draw gradient
            let start = CGPoint(x: startPoint.x * size.width, y: startPoint.y * size.height)
            let end = CGPoint(x: endPoint.x * size.width, y: endPoint.y * size.height)
            cgContext.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
    }
}
#elseif canImport(AppKit)
import AppKit

extension Image {
    /// Creates a gradient image with the specified size and colors
    static func gradientImage(
        size: CGSize = CGSize(width: 200, height: 200),
        colors: [NSColor] = [.systemBlue, .systemPurple],
        startPoint: CGPoint = CGPoint(x: 0, y: 0),
        endPoint: CGPoint = CGPoint(x: 1, y: 1)
    ) -> Image {
        let image = NSImage(size: size)
        image.lockFocus()

        // Create gradient
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: nil),
              let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // Draw gradient
        let start = CGPoint(x: startPoint.x * size.width, y: startPoint.y * size.height)
        let end = CGPoint(x: endPoint.x * size.width, y: endPoint.y * size.height)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])

        image.unlockFocus()
        return image
    }
}
#endif
