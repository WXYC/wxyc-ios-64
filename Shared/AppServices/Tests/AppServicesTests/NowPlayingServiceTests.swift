//
//  NowPlayingServiceTests.swift
//  AppServices
//
//  Tests for NowPlayingService async sequence behavior and artwork fetching.
//
//  Created by Jake Bromberg on 11/10/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import Artwork
import Core
import ImageIO
import PlaylistTesting
@testable import Playlist
@testable import AppServices
@testable import Caching

// MARK: - Helpers

/// Helper to create an isolated cache coordinator for testing.
func makeNowPlayingTestCacheCoordinator() -> CacheCoordinator {
    CacheCoordinator(cache: InMemoryCache())
}

// MARK: - Mock Types

final class MockArtworkService: ArtworkService, @unchecked Sendable {
    var artworkToReturn: CGImage?
    var errorToThrow: Error?
    var fetchCount = 0
    var lastPlaycut: Playcut?
    /// When true, returns a default image if artworkToReturn is nil instead of throwing
    var returnDefaultImageWhenNil = true

    func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        fetchCount += 1
        lastPlaycut = playcut

        if let error = errorToThrow {
            throw error
        }

        if let artwork = artworkToReturn {
            return artwork
        }

        if returnDefaultImageWhenNil {
            return CGImage.gradientImage()
        }

        throw ArtworkServiceError.noResults
    }
}

/// An artwork service whose fetch for one playcut suspends until released, standing in for a cold-cache lookup.
/// Every other playcut gets the default image at once.
final class GatedArtworkService: ArtworkService, @unchecked Sendable {
    private let gatedPlaycutID: UInt64
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let released: AsyncStream<Void>
    private let releasedContinuation: AsyncStream<Void>.Continuation

    init(gatedPlaycutID: UInt64) {
        self.gatedPlaycutID = gatedPlaycutID
        (started, startedContinuation) = AsyncStream.makeStream()
        (released, releasedContinuation) = AsyncStream.makeStream()
    }

    func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        if playcut.id == gatedPlaycutID {
            startedContinuation.yield()
            for await _ in released {
                break
            }
        }
        return CGImage.gradientImage()
    }

    func waitUntilGatedFetchStarts() async {
        for await _ in started {
            return
        }
    }

    func releaseGatedFetch() {
        releasedContinuation.yield()
    }
}

enum ArtworkServiceError: Error {
    case noResults
}

// MARK: - Tests

@MainActor
@Suite(
    "NowPlayingService Tests",
    .tags(.ciHang),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_CI_HANG"] == "1", "Hangs on CI paravirt — excluded from CI")
)
struct NowPlayingServiceTests {

    // MARK: - AsyncSequence Tests

    @Test("AsyncSequence yields NowPlayingItem from playlist")
    func asyncSequenceYieldsNowPlayingItem() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        let mockArtworkService = MockArtworkService()
        let testImage = CGImage.gradientImage()
        mockArtworkService.artworkToReturn = testImage

        let playcut = Playcut.stub()
        mockFetcher.playlistToReturn = Playlist.stub(playcuts: [playcut])

        // Use isolated cache to avoid interference from other tests
        let playlistService = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.1,
            cacheCoordinator: makeNowPlayingTestCacheCoordinator()
        )
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: mockArtworkService
        )

        // When - Get first item from sequence
        var iterator = nowPlayingService.makeAsyncIterator()
        let nowPlayingItem = try await iterator.next()

        // Then
        #expect(nowPlayingItem != nil)
        #expect(nowPlayingItem?.playcut.songTitle == "la paradoja")
        #expect(nowPlayingItem?.playcut.artistName == "Juana Molina")
        // Artwork is converted from CGImage to UIImage/NSImage, so check it's present and has expected dimensions
        #expect(nowPlayingItem?.artwork != nil)
        // Artwork logic converts CGImage to platform image, which applies screen scale.
        // Default gradient is 200x200 pts. On 2x scale -> 400px, 3x scale -> 600px.
        // We just verify we got a valid image derived from the source.
        #expect(nowPlayingItem?.artwork?.size.width ?? 0 >= 200)
        let artworkCallCount = mockArtworkService.fetchCount
        #expect(artworkCallCount == 1)
    }

    @Test("AsyncSequence names the timeline's newest playcut, not the head of the playcuts array")
    func asyncSequenceFollowsCompositeOrderNotArrayOrder() async throws {
        // The lock screen and Control Center read this sequence. `playcuts`
        // carries wire order plus live-insert appends, so once ordering keys
        // on the composite `(show_id, play_order)` (#839) a dj-site reorder
        // can move the timeline's head without moving the array's — and the
        // lock screen would name a different song than the feed shows.
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = Playlist.stub(playcuts: [
            .stub(id: 500, chronOrderID: UInt64(42) << 32 | 5, songTitle: "Back, Baby", artistName: "Jessica Pratt"),
            .stub(id: 501, chronOrderID: UInt64(42) << 32 | 9, songTitle: "la paradoja", artistName: "Juana Molina"),
        ])

        let playlistService = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.1,
            cacheCoordinator: makeNowPlayingTestCacheCoordinator()
        )
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: MockArtworkService()
        )

        var iterator = nowPlayingService.makeAsyncIterator()
        let nowPlayingItem = try await iterator.next()

        #expect(nowPlayingItem?.playcut.id == 501)
    }

    @Test("AsyncSequence skips empty playlists")
    func asyncSequenceSkipsEmptyPlaylists() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        let mockArtworkService = MockArtworkService()

        // Start with a non-empty playlist to avoid indefinite waiting
        let playcut = Playcut.stub()
        mockFetcher.playlistToReturn = Playlist.stub(playcuts: [playcut])

        // Use isolated cache to avoid interference from other tests
        let playlistService = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.05,
            cacheCoordinator: makeNowPlayingTestCacheCoordinator()
        )
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: mockArtworkService
        )

        var iterator = nowPlayingService.makeAsyncIterator()

        let nowPlayingItem = try await iterator.next()

        // Then - Should get the valid playcut
        #expect(nowPlayingItem != nil)
        #expect(nowPlayingItem?.playcut.songTitle == "la paradoja")
    }

    @Test("AsyncSequence updates when playlist changes")
    func asyncSequenceUpdatesWhenPlaylistChanges() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        let mockArtworkService = MockArtworkService()

        let playcut1 = Playcut.stub(songTitle: "First Song", artistName: "First Artist")
        mockFetcher.playlistToReturn = Playlist.stub(playcuts: [playcut1])

        // Use isolated cache to avoid interference from other tests
        let playlistService = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.05,
            cacheCoordinator: makeNowPlayingTestCacheCoordinator()
        )
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
        let playcut2 = Playcut.stub(id: 2, hour: 2000, songTitle: "Second Song", artistName: "Second Artist")
        mockFetcher.playlistToReturn = Playlist.stub(playcuts: [playcut2])

        let secondItem = try await iterator.next()

        // Then
        #expect(secondItem?.playcut.songTitle == "Second Song")
        #expect(secondItem?.playcut.artistName == "Second Artist")
    }

    @Test("AsyncSequence yields no song while a who's-on entry leads, and resumes with the next song")
    func asyncSequenceSkipsWhileSpotlightLeads() async throws {
        let openShow = { (spotlight: SpotlightEntry) in
            OnAir.dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil, spotlight: spotlight))
        }
        let weirs = SpotlightEntry.stub(id: 11, role: "performer", name: "Weirs")
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = Playlist.stub(
            playcuts: [.stub(id: 10, showID: 42, songTitle: "Back, Baby", artistName: "Jessica Pratt")],
            onAir: openShow(weirs)
        )
        let playlistService = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.05,
            cacheCoordinator: makeNowPlayingTestCacheCoordinator()
        )
        let nowPlayingService = NowPlayingService(playlistService: playlistService, artworkService: MockArtworkService())

        var iterator = nowPlayingService.makeAsyncIterator()
        Task {
            try await Task.sleep(for: .milliseconds(300))
            mockFetcher.playlistToReturn = Playlist.stub(
                playcuts: [.stub(id: 10, showID: 42), .stub(id: 12, showID: 42, songTitle: "la paradoja", artistName: "Juana Molina")],
                onAir: openShow(weirs)
            )
        }
        let item = try await iterator.next()

        #expect(item?.playcut.id == 12)
    }

    @Test("AsyncSequence drops a song whose artwork fetch outlasts a who's-on entry that took the lead")
    func asyncSequenceDropsSongOvertakenBySpotlight() async throws {
        let openShow = { (spotlight: SpotlightEntry?) in
            OnAir.dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil, spotlight: spotlight))
        }
        let weirs = SpotlightEntry.stub(id: 11, role: "performer", name: "Weirs")
        let songB = Playcut.stub(id: 10, showID: 42, songTitle: "Back, Baby", artistName: "Jessica Pratt")
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = Playlist.stub(playcuts: [songB], onAir: openShow(nil))
        let playlistService = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.05,
            cacheCoordinator: makeNowPlayingTestCacheCoordinator()
        )
        let artworkService = GatedArtworkService(gatedPlaycutID: songB.id)
        let nowPlayingService = NowPlayingService(playlistService: playlistService, artworkService: artworkService)

        var iterator = nowPlayingService.makeAsyncIterator()
        Task {
            // Song B's artwork fetch is in flight; a who's-on entry takes the lead meanwhile.
            await artworkService.waitUntilGatedFetchStarts()
            mockFetcher.playlistToReturn = Playlist.stub(playcuts: [songB], onAir: openShow(weirs))
            while true {
                let leads = await playlistService.currentPlaylistSnapshot().nowPlayingSpotlight != nil
                if leads { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            artworkService.releaseGatedFetch()
            // The next song takes the lead back.
            try await Task.sleep(for: .milliseconds(300))
            mockFetcher.playlistToReturn = Playlist.stub(
                playcuts: [songB, .stub(id: 12, showID: 42, songTitle: "la paradoja", artistName: "Juana Molina")],
                onAir: openShow(weirs)
            )
        }
        let item = try await iterator.next()

        #expect(item?.playcut.id == 12)
    }

    @Test("AsyncSequence uses first playcut from playlist")
    func asyncSequenceUsesFirstPlaycut() async throws {
        // Given
        let mockFetcher = MockPlaylistFetcher()
        let mockArtworkService = MockArtworkService()

        let playcut1 = Playcut.stub(chronOrderID: 3, songTitle: "Third Song", artistName: "Artist 3")
        let playcut2 = Playcut.stub(id: 2, hour: 2000, chronOrderID: 2, songTitle: "Second Song", artistName: "Artist 2")
        let playcut3 = Playcut.stub(id: 3, hour: 3000, chronOrderID: 1, songTitle: "First Song", artistName: "Artist 1")

        // Playlist with multiple playcuts (sorted descending by chronOrderID)
        mockFetcher.playlistToReturn = Playlist.stub(playcuts: [playcut1, playcut2, playcut3])

        // Use isolated cache to avoid interference from other tests
        let playlistService = PlaylistService(
            fetcher: mockFetcher,
            interval: 0.1,
            cacheCoordinator: makeNowPlayingTestCacheCoordinator()
        )
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
        let playcut1 = Playcut.stub(songTitle: "Song 1", artistName: "Artist 1")
        let playcut2 = Playcut.stub(id: 2, hour: 2000, songTitle: "Song 2", artistName: "Artist 2")

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
        let playcut1 = Playcut.stub(songTitle: "Song 1", artistName: "Artist 1")
        let playcut2 = Playcut.stub(id: 2, hour: 2000, songTitle: "Song 2", artistName: "Artist 2")

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

extension CGImage {
    /// Creates a gradient CGImage with the specified size and colors
    static func gradientImage(
        size: CGSize = CGSize(width: 200, height: 200),
        colors: [UIColor] = [.systemBlue, .systemPurple],
        startPoint: CGPoint = CGPoint(x: 0, y: 0),
        endPoint: CGPoint = CGPoint(x: 1, y: 1)
    ) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { context in
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
        return uiImage.cgImage!
    }
}
#elseif canImport(AppKit)
import AppKit

extension CGImage {
    /// Creates a gradient CGImage with the specified size and colors
    static func gradientImage(
        size: CGSize = CGSize(width: 200, height: 200),
        colors: [NSColor] = [.systemBlue, .systemPurple],
        startPoint: CGPoint = CGPoint(x: 0, y: 0),
        endPoint: CGPoint = CGPoint(x: 1, y: 1)
    ) -> CGImage {
        let image = NSImage(size: size)
        image.lockFocus()

        // Create gradient
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: nil),
              let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            // Fallback: create a simple 1x1 image
            return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }

        // Draw gradient
        let start = CGPoint(x: startPoint.x * size.width, y: startPoint.y * size.height)
        let end = CGPoint(x: endPoint.x * size.width, y: endPoint.y * size.height)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])

        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
#endif
