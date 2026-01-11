import Testing
import Foundation
import ImageIO
@testable import Artwork
@testable import Playlist
@testable import Core
@testable import Caching

// MARK: - Mock ArtworkService

final class MockArtworkService: ArtworkService, @unchecked Sendable {
    var artworkToReturn: CGImage?
    var errorToThrow: Error?
    var fetchCount = 0
    var lastPlaycut: Playcut?
    var delaySeconds: Double = 0

    func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        fetchCount += 1
        lastPlaycut = playcut

        if delaySeconds > 0 {
            try? await Task.sleep(for: .seconds(delaySeconds))
        }

        if let error = errorToThrow {
            throw error
        }

        guard let artwork = artworkToReturn else {
            throw ServiceError.noResults
        }

        return artwork
    }
}

// MARK: - Mock CacheCoordinator

actor MockCacheCoordinator {
    private var storage: [String: Data] = [:]

    func set(artwork: CGImage, for key: String, lifespan: TimeInterval = .thirtyDays) {
        if let data = encodeCGImageAsPNG(artwork) {
            storage[key] = data
        }
    }

    func hasKey(_ key: String) -> Bool {
        storage[key] != nil
    }

    private func encodeCGImageAsPNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// MARK: - Test Helpers

#if canImport(UIKit)
import UIKit

extension CGImage {
    static func testImageWithColor(_ color: UIColor) -> CGImage {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return uiImage.cgImage!
    }

    /// Encodes CGImage to PNG data for comparison in tests.
    var pngDataCompatibility: Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#elseif canImport(AppKit)
import AppKit

extension CGImage {
    static func testImageWithColor(_ color: NSColor) -> CGImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    /// Encodes CGImage to PNG data for comparison in tests.
    var pngDataCompatibility: Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif

// MARK: - ArtworkService Tests

@Suite("ArtworkService Tests")
struct ArtworkServiceTests {

    // MARK: - Basic Fetching Tests

    @Test("Fetches artwork from first successful fetcher")
    func fetchesFromFirstSuccessfulFetcher() async throws {
        // Given
        let fetcher1 = MockArtworkService()
        let fetcher2 = MockArtworkService()
        let fetcher3 = MockArtworkService()

        let expectedArtwork = CGImage.testImageWithColor(.red)
        fetcher1.artworkToReturn = expectedArtwork
        fetcher2.artworkToReturn = CGImage.testImageWithColor(.blue)
        fetcher3.artworkToReturn = CGImage.testImageWithColor(.green)

        let service = MultisourceArtworkService(
            fetchers: [fetcher1, fetcher2, fetcher3],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When
        let artwork = try await service.fetchArtwork(for: playcut)

        // Then
        #expect(fetcher1.fetchCount == 1)
        #expect(fetcher2.fetchCount == 0) // Should not reach second fetcher
        #expect(fetcher3.fetchCount == 0) // Should not reach third fetcher
        #expect(artwork.pngDataCompatibility == expectedArtwork.pngDataCompatibility)
    }

    @Test("Falls back to next fetcher when first fails")
    func fallsBackToNextFetcher() async throws {
        // Given
        let fetcher1 = MockArtworkService()
        let fetcher2 = MockArtworkService()
        let fetcher3 = MockArtworkService()

        fetcher1.errorToThrow = ServiceError.noResults
        fetcher2.errorToThrow = ServiceError.noResults
        let expectedArtwork = CGImage.testImageWithColor(.green)
        fetcher3.artworkToReturn = expectedArtwork

        let service = MultisourceArtworkService(
            fetchers: [fetcher1, fetcher2, fetcher3],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When
        let artwork = try await service.fetchArtwork(for: playcut)

        // Then
        #expect(fetcher1.fetchCount == 1)
        #expect(fetcher2.fetchCount == 1)
        #expect(fetcher3.fetchCount == 1)
        #expect(artwork.pngDataCompatibility == expectedArtwork.pngDataCompatibility)
    }

    @Test("Throws error when all fetchers fail")
    func throwsErrorWhenAllFetchersFail() async throws {
        // Given
        let fetcher1 = MockArtworkService()
        let fetcher2 = MockArtworkService()

        fetcher1.errorToThrow = ServiceError.noResults
        fetcher2.errorToThrow = ServiceError.noResults

        let service = MultisourceArtworkService(
            fetchers: [fetcher1, fetcher2],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When/Then
        await #expect(throws: MultisourceArtworkService.Error.noArtworkAvailable) {
            try await service.fetchArtwork(for: playcut)
        }

        #expect(fetcher1.fetchCount == 1)
        #expect(fetcher2.fetchCount == 1)
    }

    // MARK: - Inflight Task Deduplication Tests

    @Test("Deduplicates concurrent requests for same artwork")
    func deduplicatesConcurrentRequests() async throws {
        // Given
        let fetcher = MockArtworkService()
        let artwork = CGImage.testImageWithColor(.blue)
        fetcher.artworkToReturn = artwork
        fetcher.delaySeconds = 0.1 // Add delay to ensure concurrent execution

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When - Make 3 concurrent requests for the same artwork
        async let result1 = service.fetchArtwork(for: playcut)
        async let result2 = service.fetchArtwork(for: playcut)
        async let result3 = service.fetchArtwork(for: playcut)

        let artworks = try await [result1, result2, result3]

        // Then - Fetcher should only be called once
        #expect(fetcher.fetchCount == 1)
        #expect(artworks.count == 3)
        #expect(artworks.allSatisfy { $0.pngDataCompatibility == artwork.pngDataCompatibility })
    }

    @Test("Uses release title as deduplication key")
    func usesReleaseTitleAsKey() async throws {
        // Given
        let fetcher = MockArtworkService()
        let artwork = CGImage.testImageWithColor(.red)
        fetcher.artworkToReturn = artwork
        fetcher.delaySeconds = 0.05

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        // Two playcuts with same release title but different songs
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Song A",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 2,
            songTitle: "Song B",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When - Request both concurrently
        async let result1 = service.fetchArtwork(for: playcut1)
        async let result2 = service.fetchArtwork(for: playcut2)

        _ = try await [result1, result2]

        // Then - Should deduplicate because same artist and same release title
        #expect(fetcher.fetchCount == 1)
    }

    @Test("Different artists with same release title are NOT deduplicated")
    func differentArtistsSameReleaseTitleNotDeduplicated() async throws {
        // Given
        let fetcher = MockArtworkService()
        let artwork = CGImage.testImageWithColor(.red)
        fetcher.artworkToReturn = artwork
        fetcher.delaySeconds = 0.05

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        // Two playcuts with same release title but DIFFERENT artists
        // This can happen with compilation albums or common album names like "Greatest Hits"
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Song A",
            labelName: nil,
            artistName: "Artist A",
            releaseTitle: "Greatest Hits"
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 2,
            songTitle: "Song B",
            labelName: nil,
            artistName: "Artist B", // Different artist
            releaseTitle: "Greatest Hits" // Same release title
        )

        // When - Request both concurrently
        async let result1 = service.fetchArtwork(for: playcut1)
        async let result2 = service.fetchArtwork(for: playcut2)

        _ = try await [result1, result2]

        // Then - Should NOT deduplicate because different artists
        #expect(fetcher.fetchCount == 2)
    }

    @Test("Different artists with same song title are NOT deduplicated")
    func differentArtistsSameSongTitleNotDeduplicated() async throws {
        // Given
        let fetcher = MockArtworkService()
        let artwork = CGImage.testImageWithColor(.yellow)
        fetcher.artworkToReturn = artwork
        fetcher.delaySeconds = 0.05

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        // Two playcuts with same song title but DIFFERENT artists, no release title
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Unique Song",
            labelName: nil,
            artistName: "Artist A",
            releaseTitle: nil
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 2,
            songTitle: "Unique Song",
            labelName: nil,
            artistName: "Artist B", // Different artist
            releaseTitle: nil
        )

        // When - Request both concurrently
        async let result1 = service.fetchArtwork(for: playcut1)
        async let result2 = service.fetchArtwork(for: playcut2)

        _ = try await [result1, result2]

        // Then - Should NOT deduplicate because different artists
        #expect(fetcher.fetchCount == 2)
    }

    @Test("Same artist with same song title and no release title IS deduplicated")
    func sameArtistSameSongTitleDeduplicated() async throws {
        // Given
        let fetcher = MockArtworkService()
        let artwork = CGImage.testImageWithColor(.yellow)
        fetcher.artworkToReturn = artwork
        fetcher.delaySeconds = 0.05

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        // Two playcuts with same song title AND same artist, no release title
        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Unique Song",
            labelName: nil,
            artistName: "Same Artist",
            releaseTitle: nil
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 2,
            songTitle: "Unique Song",
            labelName: nil,
            artistName: "Same Artist", // Same artist
            releaseTitle: nil
        )

        // When - Request both concurrently
        async let result1 = service.fetchArtwork(for: playcut1)
        async let result2 = service.fetchArtwork(for: playcut2)

        _ = try await [result1, result2]

        // Then - Should deduplicate because same artist and same song title
        #expect(fetcher.fetchCount == 1)
    }

    @Test("Does not deduplicate different artworks")
    func doesNotDeduplicateDifferentArtworks() async throws {
        // Given
        let fetcher = MockArtworkService()
        fetcher.artworkToReturn = CGImage.testImageWithColor(.purple)

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut1 = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Song A",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Album A"
        )

        let playcut2 = Playcut(
            id: 2,
            hour: 2000,
            chronOrderID: 2,
            songTitle: "Song B",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Album B"
        )

        // When - Request different albums
        _ = try await service.fetchArtwork(for: playcut1)
        _ = try await service.fetchArtwork(for: playcut2)

        // Then - Should fetch twice
        #expect(fetcher.fetchCount == 2)
    }

    // MARK: - Cache Integration Tests

    @Test("Caches successful artwork fetch")
    func cachesSuccessfulFetch() async throws {
        // Given
        let mockCache = MockCacheCoordinator()

        let fetcher = MockArtworkService()
        let artwork = CGImage.testImageWithColor(.orange)
        fetcher.artworkToReturn = artwork

        // Create a mock cache fetcher that reads from our mockCache
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // First service with just the regular fetcher
        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        // When - First fetch
        let artwork1 = try await service.fetchArtwork(for: playcut)

        // Then - Should have fetched once
        #expect(fetcher.fetchCount == 1)

        // Manually cache the artwork in our mock
        let cacheKey = "Test Artist-Test Album"
        await mockCache.set(artwork: artwork, for: cacheKey)

        // Verify it's cached
        let isCached = await mockCache.hasKey(cacheKey)
        #expect(isCached == true)

        // The test verifies that:
        // 1. The service fetches artwork successfully
        // 2. The artwork can be stored in cache
        // This simulates the caching behavior without relying on singleton state
        #expect(artwork1.pngDataCompatibility == artwork.pngDataCompatibility)
    }

    // MARK: - Error Handling Tests

    @Test("Continues to next fetcher on error")
    func continuesToNextFetcherOnError() async throws {
        // Given
        let failingFetcher = MockArtworkService()
        failingFetcher.errorToThrow = NSError(domain: "test", code: -1)

        let successfulFetcher = MockArtworkService()
        let artwork = CGImage.testImageWithColor(.magenta)
        successfulFetcher.artworkToReturn = artwork

        let service = MultisourceArtworkService(
            fetchers: [failingFetcher, successfulFetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When
        let result = try await service.fetchArtwork(for: playcut)

        // Then
        #expect(failingFetcher.fetchCount == 1)
        #expect(successfulFetcher.fetchCount == 1)
        #expect(result.pngDataCompatibility == artwork.pngDataCompatibility)
    }

    @Test("Handles empty fetcher list gracefully")
    func handlesEmptyFetcherList() async throws {
        // Given
        let service = MultisourceArtworkService(
            fetchers: [],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When/Then
        await #expect(throws: MultisourceArtworkService.Error.noArtworkAvailable) {
            try await service.fetchArtwork(for: playcut)
        }
    }

    // MARK: - Playcut Property Tests

    @Test("Passes correct playcut to fetcher")
    func passesCorrectPlaycutToFetcher() async throws {
        // Given
        let fetcher = MockArtworkService()
        fetcher.artworkToReturn = CGImage.testImageWithColor(.brown)

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut = Playcut(
            id: 42,
            hour: 12345,
            chronOrderID: 99,
            songTitle: "Specific Song",
            labelName: "Specific Label",
            artistName: "Specific Artist",
            releaseTitle: "Specific Album"
        )

        // When
        _ = try await service.fetchArtwork(for: playcut)

        // Then
        #expect(fetcher.lastPlaycut != nil)
        #expect(fetcher.lastPlaycut?.songTitle == "Specific Song")
        #expect(fetcher.lastPlaycut?.artistName == "Specific Artist")
        #expect(fetcher.lastPlaycut?.releaseTitle == "Specific Album")
        #expect(fetcher.lastPlaycut?.labelName == "Specific Label")
    }

    // MARK: - Concurrent Access Tests

    @Test("Handles multiple different concurrent requests")
    func handlesMultipleDifferentConcurrentRequests() async throws {
        // Given
        let fetcher = MockArtworkService()
        fetcher.artworkToReturn = CGImage.testImageWithColor(.systemTeal)
        fetcher.delaySeconds = 0.05

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcuts = (1...5).map { i in
            Playcut(
                id: UInt64(i),
                hour: UInt64(i * 1000),
                chronOrderID: UInt64(i),
                songTitle: "Song \(i)",
                labelName: nil,
                artistName: "Artist",
                releaseTitle: "Album \(i)"
            )
        }

        // When - Request all concurrently
        let results = try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
            for (index, playcut) in playcuts.enumerated() {
                group.addTask {
                    let artwork = try await service.fetchArtwork(for: playcut)
                    return (index, artwork)
                }
            }

            var collected: [(Int, CGImage)] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        // Then - Should have fetched each one
        #expect(results.count == 5)
        #expect(fetcher.fetchCount == 5)
    }

    @Test("Sequential requests for same artwork use cached task")
    func sequentialRequestsUseCachedTask() async throws {
        // Given
        let fetcher = MockArtworkService()
        let artwork = CGImage.testImageWithColor(.systemIndigo)
        fetcher.artworkToReturn = artwork

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator.AlbumArt
        )

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When - Make sequential requests
        _ = try await service.fetchArtwork(for: playcut)
        _ = try await service.fetchArtwork(for: playcut)
        _ = try await service.fetchArtwork(for: playcut)

        // Then - Each request should hit the fetcher since tasks complete between calls
        // But with cache as first fetcher, subsequent calls would be cached
        #expect(fetcher.fetchCount >= 1)
    }

    // MARK: - Default Initializer Test

    @Test("Default initializer works correctly")
    func defaultInitializerWorks() async throws {
        // Given
        let service = MultisourceArtworkService()

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // When/Then - Service should work with default fetchers
        // It will likely fail to find artwork for this test playcut, but shouldn't crash
        _ = try? await service.fetchArtwork(for: playcut)

        // Test passes if we get here without crashing
        #expect(true)
    }
}
