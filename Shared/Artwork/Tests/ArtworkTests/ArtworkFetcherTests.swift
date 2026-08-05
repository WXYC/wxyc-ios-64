//
//  ArtworkFetcherTests.swift
//  Artwork
//
//  Tests for individual artwork fetcher implementations (Discogs).
//
//  Created by Jake Bromberg on 11/10/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import PlaylistTesting
@testable import Artwork
@testable import Playlist
@testable import Core
@testable import Caching

// MARK: - Mock WebSession

final class MockWebSession: WebSession, @unchecked Sendable {
    var dataToReturn: Data?
    var errorToThrow: Error?
    var requestedURLs: [URL] = []

    func data(from url: URL) async throws -> Data {
        requestedURLs.append(url)

        if let error = errorToThrow {
            throw error
        }

        guard let data = dataToReturn else {
            throw ServiceError.noResults
        }

        return data
    }
}

/// A `WebSession` that returns queued responses in order — request N gets
/// `responses[N]` — for fetchers that make more than one sequential request
/// (a search followed by an image fetch). Once queued responses are
/// exhausted, further requests throw `.noResults`.
final class SequentialMockSession: WebSession, @unchecked Sendable {
    var responses: [Data] = []
    var currentIndex = 0

    func data(from url: URL) async throws -> Data {
        defer { currentIndex += 1 }
        guard currentIndex < responses.count else {
            throw ServiceError.noResults
        }
        return responses[currentIndex]
    }
}

// MARK: - Test Helpers

#if canImport(UIKit)
import UIKit

extension CGImage {
    static var testImage: CGImage {
        // Create a simple 1x1 red image for testing
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return uiImage.cgImage!
    }
}
#elseif canImport(AppKit)
import AppKit

extension CGImage {
    static var testImage: CGImage {
        // Create a simple 1x1 red image for testing
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
#endif

// MARK: - DiscogsArtworkService Tests

@Suite(
    "DiscogsArtworkService Tests",
    .tags(.ciHang),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_CI_HANG"] == "1", "Hangs on CI paravirt — excluded from CI")
)
struct DiscogsArtworkServiceTests {

    @Test("Fetches album artwork successfully")
    func fetchAlbumArtworkSuccess() async throws {
        // Given
        let mockSession = SequentialMockSession()
        let fetcher = DiscogsArtworkService(key: "test-key", secret: "test-secret", session: mockSession)

        let playcut = Playcut.stub()

        // Mock search results with valid cover image
        let searchResults = """
        {
            "results": [
                {
                    "cover_image": "https://example.com/cover.jpg",
                    "master_id": 12345,
                    "id": 1,
                    "type": "release"
                }
            ]
        }
        """.data(using: .utf8)!

        let imageData = CGImage.testImage.pngDataCompatibility!

        mockSession.responses = [searchResults, imageData]

        // When
        let artwork = try await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(artwork.pngDataCompatibility != nil)
    }

    @Test("Skips spacer.gif images")
    func skipsSpacerGifImages() async throws {
        // Given
        let mockSession = SequentialMockSession()
        let fetcher = DiscogsArtworkService(key: "test-key", secret: "test-secret", session: mockSession)

        let playcut = Playcut.stub()

        // Mock search results with spacer.gif first, then real image
        let searchResults = """
        {
            "results": [
                {
                    "cover_image": "https://example.com/spacer.gif",
                    "master_id": 1,
                    "id": 1,
                    "type": "release"
                },
                {
                    "cover_image": "https://example.com/real-cover.jpg",
                    "master_id": 2,
                    "id": 2,
                    "type": "release"
                }
            ]
        }
        """.data(using: .utf8)!

        let imageData = CGImage.testImage.pngDataCompatibility!

        mockSession.responses = [searchResults, imageData]

        // When
        let artwork = try await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(artwork.pngDataCompatibility != nil)
    }

    @Test("Handles s/t (self-titled) album correctly")
    func handlesSelfTitledAlbum() async throws {
        // This test verifies the URL construction logic for self-titled albums
        // We can't easily test the internal URL construction, but we can verify behavior

        let mockSession = MockWebSession()
        let fetcher = DiscogsArtworkService(key: "test-key", secret: "test-secret", session: mockSession)

        let playcut = Playcut.stub(releaseTitle: "s/t")

        mockSession.errorToThrow = ServiceError.noResults

        // When
        _ = try? await fetcher.fetchArtwork(for: playcut)

        // Then - should have made a request
        #expect(mockSession.requestedURLs.count > 0)
    }

    @Test("Falls back to artist art when album art not found")
    func fallsBackToArtistArt() async throws {
        // Given
        final class CustomMockSession: WebSession, @unchecked Sendable {
            var responses: [URL: Data] = [:]
            var requestCount = 0

            func data(from url: URL) async throws -> Data {
                requestCount += 1

                // First request (album search) returns empty results
                if requestCount == 1 {
                    return """
                    {
                        "results": []
                    }
                    """.data(using: .utf8)!
                }

                // Second request (artist search) returns results
                if requestCount == 2 {
                    return """
                    {
                        "results": [
                            {
                                "cover_image": "https://example.com/artist.jpg",
                                "master_id": 123,
                                "id": 1,
                                "type": "artist"
                            }
                        ]
                    }
                    """.data(using: .utf8)!
                }

                // Third request is for the actual image
                return CGImage.testImage.pngDataCompatibility!
            }
        }

        let mockSession = CustomMockSession()
        let fetcher = DiscogsArtworkService(key: "test-key", secret: "test-secret", session: mockSession)

        let playcut = Playcut.stub()

        // When
        let artwork = try await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(artwork.pngDataCompatibility != nil)
        #expect(mockSession.requestCount == 3) // album search, artist search, image fetch
    }

    @Test("Throws error when no artwork found")
    func throwsErrorWhenNoArtwork() async throws {
        // Given
        let mockSession = MockWebSession()
        let fetcher = DiscogsArtworkService(key: "test-key", secret: "test-secret", session: mockSession)

        let playcut = Playcut.stub()

        // Mock empty search results
        let emptyResults = """
        {
            "results": []
        }
        """.data(using: .utf8)!

        mockSession.dataToReturn = emptyResults

        // When/Then
        await #expect(throws: ServiceError.self) {
            try await fetcher.fetchArtwork(for: playcut)
        }
    }
}

// MARK: - URLArtworkFetcher Tests

@Suite(
    "URLArtworkFetcher Tests",
    .tags(.ciHang),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_CI_HANG"] == "1", "Hangs on CI paravirt — excluded from CI")
)
struct URLArtworkFetcherTests {

    @Test("Fetches image when artworkURL is present")
    func fetchImageFromURL() async throws {
        let mockSession = MockWebSession()
        let fetcher = URLArtworkFetcher(session: mockSession)
        let playcut = Playcut.stub(
            artistName: "Autechre",
            releaseTitle: "Confield",
            artworkURL: URL(string: "https://example.com/artwork.jpg")
        )
        mockSession.dataToReturn = CGImage.testImage.pngDataCompatibility!

        let artwork = try await fetcher.fetchArtwork(for: playcut)

        #expect(artwork.pngDataCompatibility != nil)
        #expect(mockSession.requestedURLs.first?.absoluteString == "https://example.com/artwork.jpg")
    }

    @Test("Throws notAttempted when artworkURL is nil")
    func throwsNotAttemptedWhenNoArtworkURL() async throws {
        // Critically, this must NOT be `.noResults` — that case is reserved for
        // "the fetcher looked and found nothing" and is what populates the 30-day
        // negative cache in MultisourceArtworkService. A nil URL means backend
        // enrichment hasn't completed yet; the fetcher made no attempt, so
        // there is no verdict to cache.
        let mockSession = MockWebSession()
        let fetcher = URLArtworkFetcher(session: mockSession)
        let playcut = Playcut.stub(artworkURL: nil)

        await #expect(throws: ServiceError.notAttempted) {
            try await fetcher.fetchArtwork(for: playcut)
        }
        #expect(mockSession.requestedURLs.isEmpty)
    }

    @Test("Throws noResults when session returns non-image data")
    func throwsWhenNonImageData() async throws {
        let mockSession = MockWebSession()
        let fetcher = URLArtworkFetcher(session: mockSession)
        let playcut = Playcut.stub(
            artworkURL: URL(string: "https://example.com/artwork.jpg")
        )
        mockSession.dataToReturn = "{\"error\":\"not found\"}".data(using: .utf8)!

        await #expect(throws: ServiceError.noResults) {
            try await fetcher.fetchArtwork(for: playcut)
        }
    }

    @Test("Propagates session errors")
    func propagatesSessionError() async throws {
        let mockSession = MockWebSession()
        let fetcher = URLArtworkFetcher(session: mockSession)
        let playcut = Playcut.stub(
            artworkURL: URL(string: "https://example.com/artwork.jpg")
        )
        mockSession.errorToThrow = URLError(.badServerResponse)

        await #expect(throws: URLError.self) {
            try await fetcher.fetchArtwork(for: playcut)
        }
    }
}

// MARK: - CacheCoordinator Extension Tests

@Suite(
    "CacheCoordinator ArtworkService Tests",
    .tags(.ciHang),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_CI_HANG"] == "1", "Hangs on CI paravirt — excluded from CI")
)
struct CacheCoordinatorArtworkTests {

    @Test("Fetches cached artwork with release title")
    func fetchesCachedArtworkWithReleaseTitle() async throws {
        // Given
        let cache = CacheCoordinator.AlbumArt
        let testImage = CGImage.testImage
        let playcut = Playcut.stub()

        // Set cached artwork with correct key format: artistName-releaseTitle
        await cache.set(artwork: testImage, for: "Juana Molina-DOGA", lifespan: .thirtyDays)

        // When
        let fetchedArtwork = try await cache.fetchArtwork(for: playcut)

        // Then
        #expect(fetchedArtwork.pngDataCompatibility != nil)
    }

    @Test("Fetches cached artwork without release title")
    func fetchesCachedArtworkWithoutReleaseTitle() async throws {
        // Given
        let cache = CacheCoordinator.AlbumArt
        let testImage = CGImage.testImage
        let playcut = Playcut.stub(releaseTitle: nil)

        // Set cached artwork with correct key format: artistName-songTitle (no release title)
        await cache.set(artwork: testImage, for: "Juana Molina-la paradoja", lifespan: .thirtyDays)

        // When
        let fetchedArtwork = try await cache.fetchArtwork(for: playcut)

        // Then
        #expect(fetchedArtwork.pngDataCompatibility != nil)
    }

    @Test("Throws error when artwork not cached")
    func throwsErrorWhenNotCached() async throws {
        // Given
        let cache = CacheCoordinator.AlbumArt
        let playcut = Playcut.stub(
            songTitle: "Uncached Song",
            artistName: "Uncached Artist",
            releaseTitle: "Uncached Album"
        )

        // When/Then
        await #expect(throws: (any Error).self) {
            try await cache.fetchArtwork(for: playcut)
        }
    }

    @Test("Uses release title as cache key when available")
    func usesReleaseTitleAsCacheKey() async throws {
        // Given
        let cache = CacheCoordinator.AlbumArt
        let testImage = CGImage.testImage

        // Set with correct key format: artistName-releaseTitle
        await cache.set(artwork: testImage, for: "Some Artist-My Album", lifespan: .thirtyDays)

        // Playcut with matching release title
        let playcut = Playcut.stub(
            songTitle: "Some Song",
            artistName: "Some Artist",
            releaseTitle: "My Album"
        )

        // When
        let fetchedArtwork = try await cache.fetchArtwork(for: playcut)

        // Then
        #expect(fetchedArtwork.pngDataCompatibility != nil)
    }

    @Test("Skips empty release title")
    func skipsEmptyReleaseTitle() async throws {
        // Given
        let cache = CacheCoordinator.AlbumArt
        let testImage = CGImage.testImage

        // Set with correct key format: artistName-songTitle (empty release title is skipped)
        await cache.set(artwork: testImage, for: "Juana Molina-la paradoja", lifespan: .thirtyDays)

        // Playcut with empty release title
        let playcut = Playcut.stub(releaseTitle: "")

        // When
        let fetchedArtwork = try await cache.fetchArtwork(for: playcut)

        // Then
        #expect(fetchedArtwork.pngDataCompatibility != nil)
    }
}
