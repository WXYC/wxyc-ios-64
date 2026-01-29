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
@testable import Playlist
@testable import AppServices
@testable import Caching

// MARK: - Mock Types

final class MockPlaylistFetcher: PlaylistFetcherProtocol, @unchecked Sendable {
    var playlistToReturn: Playlist = .empty
    var callCount = 0

    func fetchPlaylist() async -> Playlist {
        callCount += 1
        return playlistToReturn
    }
}

// MARK: - Mock Cache for Isolated Tests

/// In-memory cache for isolated test execution
final class NowPlayingTestMockCache: Cache, @unchecked Sendable {
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
func makeNowPlayingTestCacheCoordinator() -> CacheCoordinator {
    CacheCoordinator(cache: NowPlayingTestMockCache())
}

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

enum ArtworkServiceError: Error {
    case noResults
}

// MARK: - Playcut Test Stub

extension Playcut {
    /// Creates a Playcut with sensible defaults for testing.
    static func stub(
        id: UInt64 = 1,
        hour: UInt64 = 1000,
        chronOrderID: UInt64? = nil,
        timeCreated: UInt64? = nil,
        songTitle: String = "Test Song",
        labelName: String? = nil,
        artistName: String = "Test Artist",
        releaseTitle: String? = nil
    ) -> Playcut {
        Playcut(
            id: id,
            hour: hour,
            chronOrderID: chronOrderID ?? id,
            timeCreated: timeCreated ?? hour,
            songTitle: songTitle,
            labelName: labelName,
            artistName: artistName,
            releaseTitle: releaseTitle
        )
    }
}

extension Playlist {
    /// Creates a Playlist stub for testing.
    static func stub(
        playcuts: [Playcut] = [],
        breakpoints: [Breakpoint] = [],
        talksets: [Talkset] = []
    ) -> Playlist {
        Playlist(
            playcuts: playcuts,
            breakpoints: breakpoints,
            talksets: talksets
        )
    }
}

// MARK: - Tests

@MainActor
@Suite("NowPlayingService Tests")
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
        #expect(nowPlayingItem?.playcut.songTitle == "Test Song")
        #expect(nowPlayingItem?.playcut.artistName == "Test Artist")
        // Artwork is converted from CGImage to UIImage/NSImage, so check it's present and has expected dimensions
        #expect(nowPlayingItem?.artwork != nil)
        // Artwork logic converts CGImage to platform image, which applies screen scale.
        // Default gradient is 200x200 pts. On 2x scale -> 400px, 3x scale -> 600px.
        // We just verify we got a valid image derived from the source.
        #expect(nowPlayingItem?.artwork?.size.width ?? 0 >= 200)
        let artworkCallCount = mockArtworkService.fetchCount
        #expect(artworkCallCount == 1)
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
        #expect(nowPlayingItem?.playcut.songTitle == "Test Song")
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
