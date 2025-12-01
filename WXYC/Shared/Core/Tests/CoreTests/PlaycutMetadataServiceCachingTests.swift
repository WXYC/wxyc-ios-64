//
//  PlaycutMetadataServiceCachingTests.swift
//  CoreTests
//
//  Tests for PlaycutMetadataService caching functionality
//

import Testing
import Foundation
@testable import Core

// MARK: - Mock Cache

final class MockCache: Cache, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    var getCallCount = 0
    var setCallCount = 0
    var lastSetKey: String?
    var lastGetKey: String?
    
    func object(for key: String) -> Data? {
        getCallCount += 1
        lastGetKey = key
        return storage[key]
    }
    
    func set(object: Data?, for key: String) {
        setCallCount += 1
        lastSetKey = key
        if let object {
            storage[key] = object
        } else {
            storage.removeValue(forKey: key)
        }
    }
    
    func allRecords() -> any Sequence<(String, Data)> {
        Array(storage.map { ($0.key, $0.value) })
    }
    
    func reset() {
        storage.removeAll()
        getCallCount = 0
        setCallCount = 0
        lastSetKey = nil
        lastGetKey = nil
    }
}

// MARK: - Mock WebSession for Metadata Service

final class MetadataMockWebSession: WebSession, @unchecked Sendable {
    var responses: [String: Data] = [:]
    var requestedURLs: [URL] = []
    var requestCount = 0
    
    func data(from url: URL) async throws -> Data {
        requestCount += 1
        requestedURLs.append(url)
        
        // Return matching response based on URL path
        for (pattern, data) in responses {
            if url.absoluteString.contains(pattern) {
                return data
            }
        }
        
        throw ServiceError.noResults
    }
    
    func reset() {
        responses.removeAll()
        requestedURLs.removeAll()
        requestCount = 0
    }
}

// MARK: - PlaycutMetadataService Caching Tests

@Suite("PlaycutMetadataService Caching Tests")
struct PlaycutMetadataServiceCachingTests {
    
    @Test("Returns cached metadata without making API calls")
    func returnsCachedMetadata() async throws {
        // Given
        let mockCache = MockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)
        
        let playcut = Playcut(
            id: 12345,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test Song",
            labelName: "Test Label",
            artistName: "Test Artist",
            releaseTitle: "Test Album"
        )
        
        // Pre-populate cache
        let cachedMetadata = PlaycutMetadata(
            label: "Cached Label",
            releaseYear: 2024,
            discogsURL: URL(string: "https://discogs.com/test"),
            artistBio: "Cached bio",
            wikipediaURL: nil,
            spotifyURL: URL(string: "https://spotify.com/test"),
            appleMusicURL: nil,
            youtubeMusicURL: nil,
            bandcampURL: nil,
            soundcloudURL: nil
        )
        await cache.set(value: cachedMetadata, for: "playcut-metadata-12345", lifespan: 3600)
        
        // Reset counters after cache setup
        mockSession.reset()
        mockCache.getCallCount = 0
        
        // When
        let result = await service.fetchMetadata(for: playcut)
        
        // Then
        #expect(result.label == "Cached Label")
        #expect(result.releaseYear == 2024)
        #expect(result.artistBio == "Cached bio")
        #expect(mockSession.requestCount == 0, "Should not make any API calls when cached")
    }
    
    @Test("Fetches from API and caches result on cache miss")
    func fetchesAndCachesOnMiss() async throws {
        // Given
        let mockCache = MockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)
        
        let playcut = Playcut(
            id: 99999,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "New Song",
            labelName: "New Label",
            artistName: "New Artist",
            releaseTitle: "New Album"
        )
        
        // Mock Discogs search response (empty results for simplicity)
        let emptyDiscogsResults = """
        {
            "results": []
        }
        """.data(using: .utf8)!
        mockSession.responses["api.discogs.com"] = emptyDiscogsResults
        
        // Mock iTunes response (empty)
        let emptyiTunesResults = """
        {
            "results": []
        }
        """.data(using: .utf8)!
        mockSession.responses["itunes.apple.com"] = emptyiTunesResults
        
        // When
        let result = await service.fetchMetadata(for: playcut)
        
        // Then
        #expect(result.label == "New Label") // Falls back to playcut's label
        #expect(mockCache.setCallCount > 0, "Should cache the result")
        #expect(mockCache.lastSetKey == "playcut-metadata-99999")
    }
    
    @Test("Uses correct cache key format")
    func usesCorrectCacheKey() async throws {
        // Given
        let mockCache = MockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)
        
        let playcut = Playcut(
            id: 42,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test",
            labelName: nil,
            artistName: "Artist",
            releaseTitle: nil
        )
        
        // Mock empty responses
        mockSession.responses["api.discogs.com"] = """{"results": []}""".data(using: .utf8)!
        mockSession.responses["itunes.apple.com"] = """{"results": []}""".data(using: .utf8)!
        
        // When
        _ = await service.fetchMetadata(for: playcut)
        
        // Then
        #expect(mockCache.lastGetKey == "playcut-metadata-42")
        #expect(mockCache.lastSetKey == "playcut-metadata-42")
    }
    
    @Test("Second fetch returns cached data without API call")
    func secondFetchReturnsCached() async throws {
        // Given
        let mockCache = MockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)
        
        let playcut = Playcut(
            id: 555,
            hour: 1000,
            chronOrderID: 1,
            songTitle: "Test",
            labelName: "Label",
            artistName: "Artist",
            releaseTitle: "Album"
        )
        
        // Mock responses
        mockSession.responses["api.discogs.com"] = """{"results": []}""".data(using: .utf8)!
        mockSession.responses["itunes.apple.com"] = """{"results": []}""".data(using: .utf8)!
        
        // When - first fetch
        _ = await service.fetchMetadata(for: playcut)
        let firstRequestCount = mockSession.requestCount
        
        // When - second fetch
        _ = await service.fetchMetadata(for: playcut)
        let secondRequestCount = mockSession.requestCount
        
        // Then
        #expect(secondRequestCount == firstRequestCount, "Second fetch should not make additional API calls")
    }
}



