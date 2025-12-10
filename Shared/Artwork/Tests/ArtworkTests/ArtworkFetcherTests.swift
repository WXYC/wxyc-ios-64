import Testing
import Foundation
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

// MARK: - Test Helpers

#if canImport(UIKit)
import UIKit

extension Image {
    static var testImage: Image {
        // Create a simple 1x1 red image for testing
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#elseif canImport(AppKit)
import AppKit

extension Image {
    static var testImage: Image {
        // Create a simple 1x1 red image for testing
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
}
#endif

// MARK: - iTunesArtworkService Tests

@Suite("iTunesArtworkService Tests")
struct iTunesArtworkServiceTests {

    @Test("Fetches artwork successfully for album")
    func fetchArtworkSuccessWithAlbum() async throws {
        // Given
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

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // Mock search results
        let searchResults = iTunes.SearchResults(
            results: [
                iTunes.SearchResults.Item(artworkUrl100: URL(string: "https://example.com/artwork.jpg")!)
            ]
        )
        let searchData = try JSONEncoder().encode(searchResults)
        let imageData = Image.testImage.pngDataCompatibility!

        let sequentialSession = SequentialMockSession()
        sequentialSession.responses = [searchData, imageData]
        let fetcher = iTunesArtworkService(session: sequentialSession)

        // When
        let result = try await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(result.pngDataCompatibility != nil)
    }

    @Test("Fetches artwork successfully for song without album")
    func fetchArtworkSuccessWithoutAlbum() async throws {
        // Given
        final class SequentialMockSession: WebSession, @unchecked Sendable {
            var responses: [Data] = []
            var currentIndex = 0
            var requestedURLs: [URL] = []

            func data(from url: URL) async throws -> Data {
                requestedURLs.append(url)
                defer { currentIndex += 1 }
                guard currentIndex < responses.count else {
                    throw ServiceError.noResults
                }
                return responses[currentIndex]
            }
        }

        let mockSession = SequentialMockSession()
        let fetcher = iTunesArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: nil
        )

        let searchResults = iTunes.SearchResults(
            results: [
                iTunes.SearchResults.Item(artworkUrl100: URL(string: "https://example.com/artwork.jpg")!)
            ]
        )
        let searchData = try JSONEncoder().encode(searchResults)
        let imageData = Image.testImage.pngDataCompatibility!

        mockSession.responses = [searchData, imageData]

        // When
        let artwork = try await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(artwork.pngDataCompatibility != nil)
        #expect(mockSession.requestedURLs.count == 2)
        #expect(mockSession.requestedURLs[0].absoluteString.contains("entity=song"))
    }

    @Test("Throws error when no results found")
    func throwsErrorWhenNoResults() async throws {
        // Given
        let mockSession = MockWebSession()
        let fetcher = iTunesArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        let searchResults = iTunes.SearchResults(results: [])
        let searchData = try JSONEncoder().encode(searchResults)
        mockSession.dataToReturn = searchData

        // When/Then
        await #expect(throws: ServiceError.self) {
            try await fetcher.fetchArtwork(for: playcut)
        }
    }

    @Test("Constructs correct search URL for album")
    func constructsCorrectSearchURLForAlbum() async throws {
        // Given
        let mockSession = MockWebSession()
        let fetcher = iTunesArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Radiohead",
            releaseTitle: "OK Computer"
        )

        mockSession.errorToThrow = ServiceError.noResults

        // When
        _ = try? await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(mockSession.requestedURLs.count == 1)
        let url = mockSession.requestedURLs[0]
        #expect(url.absoluteString.contains("Radiohead"))
        #expect(url.absoluteString.contains("OK%20Computer") || url.absoluteString.contains("OK+Computer"))
        #expect(url.absoluteString.contains("entity=album"))
    }
}

// MARK: - LastFMArtworkService Tests

@Suite("LastFMArtworkService Tests")
struct LastFMArtworkServiceTests {

    @Test("Fetches artwork successfully")
    func fetchArtworkSuccess() async throws {
        // Given
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

        let mockSession = SequentialMockSession()
        let fetcher = LastFMArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // Mock search response
        let searchResponse = LastFM.SearchResponse(
            album: LastFM.Album(
                image: [
                    LastFM.Album.AlbumArt(url: URL(string: "https://example.com/small.jpg")!, size: .small),
                    LastFM.Album.AlbumArt(url: URL(string: "https://example.com/large.jpg")!, size: .large),
                    LastFM.Album.AlbumArt(url: URL(string: "https://example.com/mega.jpg")!, size: .mega)
                ]
            )
        )
        let searchData = try JSONEncoder().encode(searchResponse)
        let imageData = Image.testImage.pngDataCompatibility!

        mockSession.responses = [searchData, imageData]

        // When
        let artwork = try await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(artwork.pngDataCompatibility != nil)
    }

    @Test("Selects largest album art")
    func selectsLargestAlbumArt() async throws {
        // Given
        let album = LastFM.Album(
            image: [
                LastFM.Album.AlbumArt(url: URL(string: "https://example.com/small.jpg")!, size: .small),
                LastFM.Album.AlbumArt(url: URL(string: "https://example.com/medium.jpg")!, size: .medium),
                LastFM.Album.AlbumArt(url: URL(string: "https://example.com/mega.jpg")!, size: .mega),
                LastFM.Album.AlbumArt(url: URL(string: "https://example.com/large.jpg")!, size: .large)
            ]
        )

        // When
        let largestArt = album.largestAlbumArt

        // Then
        #expect(largestArt.size == .mega)
        #expect(largestArt.url.absoluteString.contains("mega.jpg"))
    }

    @Test("AlbumArt size comparison works correctly")
    func albumArtSizeComparison() async throws {
        #expect(LastFM.Album.AlbumArt.Size.small < .medium)
        #expect(LastFM.Album.AlbumArt.Size.medium < .large)
        #expect(LastFM.Album.AlbumArt.Size.large < .extralarge)
        #expect(LastFM.Album.AlbumArt.Size.extralarge < .mega)
        #expect(LastFM.Album.AlbumArt.Size.unknown < .small)
    }

    @Test("Constructs correct search URL")
    func constructsCorrectSearchURL() async throws {
        // Given
        let mockSession = MockWebSession()
        let fetcher = LastFMArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Paranoid Android",
            labelName: nil,
            artistName: "Radiohead",
            releaseTitle: "OK Computer"
        )

        mockSession.errorToThrow = ServiceError.noResults

        // When
        _ = try? await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(mockSession.requestedURLs.count == 1)
        let url = mockSession.requestedURLs[0]
        #expect(url.absoluteString.contains("ws.audioscrobbler.com"))
        #expect(url.absoluteString.contains("method=album.getInfo"))
        #expect(url.absoluteString.contains("artist=Radiohead"))
        #expect(url.absoluteString.contains("album=OK%20Computer") || url.absoluteString.contains("album=OK+Computer"))
        #expect(url.absoluteString.contains("format=json"))
    }
}

// MARK: - DiscogsArtworkService Tests

@Suite("DiscogsArtworkService Tests")
struct DiscogsArtworkServiceTests {

    @Test("Fetches album artwork successfully")
    func fetchAlbumArtworkSuccess() async throws {
        // Given
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

        let mockSession = SequentialMockSession()
        let fetcher = DiscogsArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

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

        let imageData = Image.testImage.pngDataCompatibility!

        mockSession.responses = [searchResults, imageData]

        // When
        let artwork = try await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(artwork.pngDataCompatibility != nil)
    }

    @Test("Skips spacer.gif images")
    func skipsSpacerGifImages() async throws {
        // Given
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

        let mockSession = SequentialMockSession()
        let fetcher = DiscogsArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

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

        let imageData = Image.testImage.pngDataCompatibility!

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
        let fetcher = DiscogsArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "s/t"
        )

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
                return Image.testImage.pngDataCompatibility!
            }
        }

        let mockSession = CustomMockSession()
        let fetcher = DiscogsArtworkService(session: mockSession)

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
        let artwork = try await fetcher.fetchArtwork(for: playcut)

        // Then
        #expect(artwork.pngDataCompatibility != nil)
        #expect(mockSession.requestCount == 3) // album search, artist search, image fetch
    }

    @Test("Throws error when no artwork found")
    func throwsErrorWhenNoArtwork() async throws {
        // Given
        let mockSession = MockWebSession()
        let fetcher = DiscogsArtworkService(session: mockSession)

        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

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

// MARK: - CacheCoordinator Extension Tests

@Suite("CacheCoordinator ArtworkService Tests")
struct CacheCoordinatorArtworkTests {

    @Test("Fetches cached artwork with release title")
    func fetchesCachedArtworkWithReleaseTitle() async throws {
        // Given
        let cache = CacheCoordinator.AlbumArt
        let testImage = Image.testImage
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )

        // Set cached artwork
        await cache.set(artwork: testImage, for: "Test Album")

        // When
        let fetchedArtwork = try await cache.fetchArtwork(for: playcut)

        // Then
        #expect(fetchedArtwork.pngDataCompatibility != nil)
    }

    @Test("Fetches cached artwork without release title")
    func fetchesCachedArtworkWithoutReleaseTitle() async throws {
        // Given
        let cache = CacheCoordinator.AlbumArt
        let testImage = Image.testImage
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: nil
        )

        // Set cached artwork with song+artist key
        await cache.set(artwork: testImage, for: "Test SongTest Artist")

        // When
        let fetchedArtwork = try await cache.fetchArtwork(for: playcut)

        // Then
        #expect(fetchedArtwork.pngDataCompatibility != nil)
    }

    @Test("Throws error when artwork not cached")
    func throwsErrorWhenNotCached() async throws {
        // Given
        let cache = CacheCoordinator.AlbumArt
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Uncached Song",
            labelName: nil,
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
        let testImage = Image.testImage

        // Set with release title as key
        await cache.set(artwork: testImage, for: "My Album")

        // Playcut with matching release title
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Some Song",
            labelName: nil,
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
        let testImage = Image.testImage

        // Set with song+artist key
        await cache.set(artwork: testImage, for: "Test SongTest Artist")

        // Playcut with empty release title
        let playcut = Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: nil,
            artistName: "Test Artist",
            releaseTitle: ""
        )

        // When
        let fetchedArtwork = try await cache.fetchArtwork(for: playcut)

        // Then
        #expect(fetchedArtwork.pngDataCompatibility != nil)
    }
}
