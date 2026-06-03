//
//  ArtworkServiceTests.swift
//  Artwork
//
//  Actor-level concerns for MultisourceArtworkService: fetcher-chain ordering,
//  in-flight deduplication, negative-cache (definitive vs. transient errors),
//  and the `addFetcher` / `cacheExternalArtwork` / `clearNegativeCache` APIs.
//
//  Cache-lookup correctness (key shape, TTL, hit/miss, decoding) lives in
//  CacheCoordinatorTests, CachedFetchTests, and CacheCoordinatorArtworkTests
//  (the latter colocated in ArtworkFetcherTests.swift). Do not re-add through-
//  the-actor tests that simply re-assert lower-level cache behavior.
//
//  Created by Jake Bromberg on 11/10/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import ImageIO
import PlaylistTesting
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

@Suite(
    "ArtworkService Tests",
    .tags(.slow),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_SLOW"] == "1", "Hangs on CI paravirt — excluded from CI")
)
struct ArtworkServiceTests {

    /// Creates a unique Playcut for each test invocation to avoid error cache collisions
    /// from the persistent DiskCache used by CacheCoordinator.
    private func uniquePlaycut() -> Playcut {
        Playcut.stub(artistName: UUID().uuidString)
    }

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
            cacheCoordinator: CacheCoordinator(cache: DiskCache())
        )

        let playcut = uniquePlaycut()

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
            cacheCoordinator: CacheCoordinator(cache: DiskCache())
        )

        let playcut = uniquePlaycut()

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
            cacheCoordinator: CacheCoordinator(cache: DiskCache())
        )

        let playcut = uniquePlaycut()

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
            cacheCoordinator: CacheCoordinator(cache: DiskCache())
        )

        let playcut = uniquePlaycut()

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

    @Test(
        "In-flight deduplication is keyed by (artist, release ?? song)",
        arguments: ArtworkDedupCase.allCases
    )
    func deduplicationKeyResolution(testCase: ArtworkDedupCase) async throws {
        let fetcher = MockArtworkService()
        fetcher.artworkToReturn = CGImage.testImageWithColor(.red)
        fetcher.delaySeconds = 0.05

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))
        )

        let playcut1 = Playcut.stub(
            songTitle: testCase.song1,
            artistName: testCase.artist1,
            releaseTitle: testCase.release1
        )
        let playcut2 = Playcut.stub(
            id: 2,
            hour: 2000,
            songTitle: testCase.song2,
            artistName: testCase.artist2,
            releaseTitle: testCase.release2
        )

        async let result1 = service.fetchArtwork(for: playcut1)
        async let result2 = service.fetchArtwork(for: playcut2)
        _ = try await [result1, result2]

        #expect(fetcher.fetchCount == testCase.expectedFetchCount, "\(testCase.description)")
    }

    @Test("Does not deduplicate different artworks")
    func doesNotDeduplicateDifferentArtworks() async throws {
        // Given
        let fetcher = MockArtworkService()
        fetcher.artworkToReturn = CGImage.testImageWithColor(.purple)

        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))
        )

        let playcut1 = Playcut.stub(songTitle: "Song A", releaseTitle: "Album A")

        let playcut2 = Playcut.stub(id: 2, hour: 2000, songTitle: "Song B", releaseTitle: "Album B")

        // When - Request different albums
        _ = try await service.fetchArtwork(for: playcut1)
        _ = try await service.fetchArtwork(for: playcut2)

        // Then - Should fetch twice
        #expect(fetcher.fetchCount == 2)
    }

    // MARK: - Error Handling Tests

    @Test("Handles empty fetcher list gracefully")
    func handlesEmptyFetcherList() async throws {
        // Given
        let service = MultisourceArtworkService(
            fetchers: [],
            cacheCoordinator: CacheCoordinator(cache: DiskCache())
        )

        let playcut = uniquePlaycut()

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
            cacheCoordinator: CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))
        )

        let playcut = Playcut.stub(
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
            cacheCoordinator: CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))
        )

        let playcuts: [Playcut] = (1...5).map { i in
            Playcut.stub(
                id: UInt64(i),
                hour: UInt64(i * 1000),
                songTitle: "Song \(i)",
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

    // MARK: - Default Initializer Test

    @Test("Default initializer creates service without crashing")
    func defaultInitializerWorks() async throws {
        // Given/When - Use default fetchers (real network services)
        let service = MultisourceArtworkService()

        // Then - Service should handle a missing artwork lookup gracefully
        let playcut = uniquePlaycut()
        do {
            _ = try await service.fetchArtwork(for: playcut)
        } catch {
            // Expected: no real artwork exists for stub playcut
            #expect(error is MultisourceArtworkService.Error)
        }
    }

    // MARK: - Negative Cache Tests

    @Test("Caches definitive not-found errors in separate error cache")
    func cachesDefinitiveErrors() async throws {
        let fetcher = MockArtworkService()
        fetcher.errorToThrow = ServiceError.noResults

        let errorCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-errors-\(UUID().uuidString)"))
        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator(cache: DiskCache()),
            errorCache: errorCache
        )

        let playcut = uniquePlaycut()

        // First call: fetcher fails with noResults, error should be cached
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}

        // Second call: should hit the error cache without calling the fetcher again
        let countBefore = fetcher.fetchCount
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == countBefore)
    }

    @Test("Does not cache server errors (5xx) so they are retried")
    func doesNotCacheServerErrors() async throws {
        let fetcher = MockArtworkService()
        fetcher.errorToThrow = URLError(.badServerResponse)

        let errorCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-errors-\(UUID().uuidString)"))
        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator(cache: DiskCache()),
            errorCache: errorCache
        )

        let playcut = uniquePlaycut()

        // First call: fetcher fails with server error
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == 1)

        // Second call: should retry (not cached), so fetcher count increases
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == 2)
    }

    @Test("Positive cache takes precedence over negative cache")
    func positiveCacheTakesPrecedenceOverNegativeCache() async throws {
        // Given: a service where all fetchers fail
        let fetcher = MockArtworkService()
        fetcher.errorToThrow = ServiceError.noResults

        let artworkCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-pos-\(UUID().uuidString)"))
        let errorCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-errors-\(UUID().uuidString)"))
        let service = MultisourceArtworkService(
            fetchers: [artworkCache, fetcher],
            cacheCoordinator: artworkCache,
            errorCache: errorCache
        )

        let playcut = uniquePlaycut()

        // First call: fails and sets negative cache entry
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}

        // Externally store artwork in positive cache (simulates detail view caching)
        let testImage = CGImage.testImageWithColor(.green)
        await artworkCache.set(artwork: testImage, for: playcut.artworkCacheKey, lifespan: .thirtyDays)

        // When: fetching again with negative cache still present
        // Then: positive cache should win
        let result = try await service.fetchArtwork(for: playcut)
        #expect(result.width > 0)
    }

    @Test("cacheExternalArtwork stores artwork and clears negative cache")
    func cacheExternalArtworkStoresAndClearsNegativeCache() async throws {
        // Given: a service where all fetchers fail
        let fetcher = MockArtworkService()
        fetcher.errorToThrow = ServiceError.noResults

        let artworkCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-ext-\(UUID().uuidString)"))
        let errorCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-errors-\(UUID().uuidString)"))
        let service = MultisourceArtworkService(
            fetchers: [artworkCache, fetcher],
            cacheCoordinator: artworkCache,
            errorCache: errorCache
        )

        let playcut = uniquePlaycut()

        // First call: fails and sets negative cache entry
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == 1)

        // When: store artwork externally
        let testImage = CGImage.testImageWithColor(.cyan)
        await service.cacheExternalArtwork(testImage, for: playcut)

        // Then: fetch should succeed from cache without hitting the fetcher again
        let result = try await service.fetchArtwork(for: playcut)
        #expect(result.width > 0)
        #expect(fetcher.fetchCount == 1) // fetcher not called again
    }

    @Test("clearNegativeCache allows retrying previously failed lookups")
    func clearNegativeCacheAllowsRetry() async throws {
        let fetcher = MockArtworkService()
        fetcher.errorToThrow = ServiceError.noResults

        let errorCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-errors-\(UUID().uuidString)"))
        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator(cache: DiskCache()),
            errorCache: errorCache
        )

        let playcut = uniquePlaycut()

        // First call: fails and caches the error
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == 1)

        // Clear negative cache
        await service.clearNegativeCache()

        // Provide artwork so next call succeeds
        fetcher.errorToThrow = nil
        fetcher.artworkToReturn = CGImage.testImageWithColor(.blue)

        // Should retry (error cache cleared) and succeed
        let result = try await service.fetchArtwork(for: playcut)
        #expect(fetcher.fetchCount == 2)
        #expect(result.width > 0)
    }

    // MARK: - Transient Error Caching Tests
    //
    // Transient URLErrors (timeouts, cancellations, network drops) must not
    // populate the negative cache. Cancellation in particular is the launch-race
    // path: a row's `.task` can be cancelled mid-flight when the view is
    // reconstructed for any reason, and persisting that as `noArtworkAvailable`
    // for 30 days would block every retry.

    @Test(
        "Does not cache transient URLErrors so subsequent fetches retry",
        arguments: [
            URLError.Code.timedOut,
            URLError.Code.cancelled,
            URLError.Code.networkConnectionLost,
            URLError.Code.notConnectedToInternet,
        ]
    )
    func doesNotCacheTransientErrors(code: URLError.Code) async throws {
        let fetcher = MockArtworkService()
        fetcher.errorToThrow = URLError(code)

        let errorCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-errors-\(UUID().uuidString)"))
        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator(cache: DiskCache()),
            errorCache: errorCache
        )

        let playcut = uniquePlaycut()

        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == 1)

        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == 2, "\(code) should not be negatively cached")
    }

    // MARK: - Not-Attempted Caching Tests
    //
    // A fetcher that signals it didn't actually attempt — e.g. URLArtworkFetcher
    // when the playcut has no artwork URL yet because backend enrichment hasn't
    // completed — must not poison the 30-day negative cache. Otherwise a track
    // whose artwork URL arrives on a later poll would stay blank for 30 days,
    // the chain shadowed by a verdict that was never actually made.

    @Test("Does not cache .notAttempted so subsequent fetches retry")
    func doesNotCacheNotAttempted() async throws {
        let fetcher = MockArtworkService()
        fetcher.errorToThrow = ServiceError.notAttempted

        let errorCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-errors-\(UUID().uuidString)"))
        let service = MultisourceArtworkService(
            fetchers: [fetcher],
            cacheCoordinator: CacheCoordinator(cache: DiskCache()),
            errorCache: errorCache
        )

        let playcut = uniquePlaycut()

        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == 1)

        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(fetcher.fetchCount == 2, ".notAttempted must not be negatively cached")
    }

    @Test("Caches negative when a conclusive .noResults occurs alongside .notAttempted")
    func cachesNegativeWhenMixedWithNotAttempted() async throws {
        // Mixed chain: the URL fetcher had no URL (.notAttempted) but the Discogs
        // fallback genuinely searched and came up empty (.noResults). That second
        // outcome IS a conclusive verdict and should still be cached — otherwise
        // we'd hammer Discogs every 30s poll for tracks that simply have no art.
        let urlLike = MockArtworkService()
        urlLike.errorToThrow = ServiceError.notAttempted

        let discogsLike = MockArtworkService()
        discogsLike.errorToThrow = ServiceError.noResults

        let errorCache = CacheCoordinator(cache: DiskCache(subdirectory: "test-errors-\(UUID().uuidString)"))
        let service = MultisourceArtworkService(
            fetchers: [urlLike, discogsLike],
            cacheCoordinator: CacheCoordinator(cache: DiskCache()),
            errorCache: errorCache
        )

        let playcut = uniquePlaycut()

        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(urlLike.fetchCount == 1)
        #expect(discogsLike.fetchCount == 1)

        // Second call must hit the negative cache — neither fetcher should run again.
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(urlLike.fetchCount == 1, "a conclusive .noResults must still poison the negative cache")
        #expect(discogsLike.fetchCount == 1)
    }

    // MARK: - addFetcher Tests

    @Test("addFetcher exposes the new fetcher to subsequent fetchArtwork calls")
    func addFetcherExposesNewFetcher() async throws {
        let original = MockArtworkService()
        original.errorToThrow = ServiceError.noResults

        let added = MockArtworkService()
        added.artworkToReturn = CGImage.testImageWithColor(.green)

        let service = MultisourceArtworkService(
            fetchers: [original],
            cacheCoordinator: CacheCoordinator(cache: DiskCache(subdirectory: "test-add-\(UUID().uuidString)")),
            errorCache: CacheCoordinator(cache: DiskCache(subdirectory: "test-add-err-\(UUID().uuidString)"))
        )

        let playcut = uniquePlaycut()

        // First call: only the original fetcher exists — fails.
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(original.fetchCount == 1)
        #expect(added.fetchCount == 0)

        // Augment the chain.
        await service.addFetcher(added)

        // Second call: the new fetcher should now be tried (after the original
        // fails again) and succeed.
        let result = try await service.fetchArtwork(for: playcut)
        #expect(original.fetchCount == 2)
        #expect(added.fetchCount == 1)
        #expect(result.width > 0)
    }

    @Test("addFetcher clears the negative cache so previously-failed lookups can retry")
    func addFetcherClearsNegativeCache() async throws {
        let original = MockArtworkService()
        original.errorToThrow = ServiceError.noResults

        let added = MockArtworkService()
        added.artworkToReturn = CGImage.testImageWithColor(.blue)

        let service = MultisourceArtworkService(
            fetchers: [original],
            cacheCoordinator: CacheCoordinator(cache: DiskCache(subdirectory: "test-add2-\(UUID().uuidString)")),
            errorCache: CacheCoordinator(cache: DiskCache(subdirectory: "test-add2-err-\(UUID().uuidString)"))
        )

        let playcut = uniquePlaycut()

        // First call: fails, populates the negative cache.
        do { _ = try await service.fetchArtwork(for: playcut) } catch {}
        #expect(original.fetchCount == 1)

        // addFetcher must clear the negative cache as part of its contract — otherwise
        // the freshly-augmented chain would be silently bypassed by the cached error.
        await service.addFetcher(added)

        let result = try await service.fetchArtwork(for: playcut)
        #expect(added.fetchCount == 1, "Newly-added fetcher must run despite the prior negative-cache entry")
        #expect(result.width > 0)
    }
}

/// Inputs and expected outcome for `deduplicationKeyResolution`.
struct ArtworkDedupCase: Sendable, CustomStringConvertible {
    let description: String
    let artist1: String
    let artist2: String
    let song1: String
    let song2: String
    let release1: String?
    let release2: String?
    let expectedFetchCount: Int

    static let allCases: [ArtworkDedupCase] = [
        // Same artist, same release title, different songs → release title wins, dedup.
        ArtworkDedupCase(
            description: "same artist + same release title ⇒ dedup",
            artist1: "uniqueArtist", artist2: "uniqueArtist",
            song1: "Song A", song2: "Song B",
            release1: "Test Album", release2: "Test Album",
            expectedFetchCount: 1
        ),
        // Different artists with the same release title (e.g., compilation) → different keys, no dedup.
        ArtworkDedupCase(
            description: "different artists + same release title ⇒ no dedup",
            artist1: "Artist A", artist2: "Artist B",
            song1: "Song A", song2: "Song B",
            release1: "Greatest Hits", release2: "Greatest Hits",
            expectedFetchCount: 2
        ),
        // Different artists with the same song title and no release → different keys, no dedup.
        ArtworkDedupCase(
            description: "different artists + same song title ⇒ no dedup",
            artist1: "Artist A", artist2: "Artist B",
            song1: "Unique Song", song2: "Unique Song",
            release1: nil, release2: nil,
            expectedFetchCount: 2
        ),
        // Same artist, same song, no release → same key, dedup.
        ArtworkDedupCase(
            description: "same artist + same song title ⇒ dedup",
            artist1: "Same Artist", artist2: "Same Artist",
            song1: "Unique Song", song2: "Unique Song",
            release1: nil, release2: nil,
            expectedFetchCount: 1
        ),
    ]
}
