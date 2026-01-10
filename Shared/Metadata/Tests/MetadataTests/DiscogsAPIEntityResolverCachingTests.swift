//
//  DiscogsAPIEntityResolverCachingTests.swift
//  MetadataTests
//
//  Tests for DiscogsAPIEntityResolver caching functionality
//

import Testing
import Foundation
import Core
@testable import Caching
@testable import Metadata

// MARK: - Mock Cache for Entity Resolver Tests

final class EntityResolverMockCache: Cache, @unchecked Sendable {
    private var dataStorage: [String: Data] = [:]
    private var metadataStorage: [String: CacheMetadata] = [:]
    var getCallCount = 0
    var setCallCount = 0
    var keysSet: [String] = []
    var lastGetKey: String?
    var lastSetKey: String?
    
    func metadata(for key: String) -> CacheMetadata? {
        getCallCount += 1
        lastGetKey = key
        return metadataStorage[key]
    }
    
    func data(for key: String) -> Data? {
        return dataStorage[key]
    }
    
    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        setCallCount += 1
        lastSetKey = key
        keysSet.append(key)
        if let data {
            dataStorage[key] = data
            metadataStorage[key] = metadata
        } else {
            remove(for: key)
        }
    }
    
    func remove(for key: String) {
        dataStorage.removeValue(forKey: key)
        metadataStorage.removeValue(forKey: key)
    }
    
    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        metadataStorage.map { ($0.key, $0.value) }
    }

    func clearAll() {
        dataStorage.removeAll()
        metadataStorage.removeAll()
    }

    func totalSize() -> Int64 {
        dataStorage.values.reduce(0) { $0 + Int64($1.count) }
    }
}

// MARK: - Mock WebSession for Entity Resolver

final class EntityResolverMockWebSession: WebSession, @unchecked Sendable {
    var responses: [String: Data] = [:]
    var requestedURLs: [URL] = []
    var requestCount = 0
    var shouldFail = false
    
    func data(from url: URL) async throws -> Data {
        requestCount += 1
        requestedURLs.append(url)
        
        if shouldFail {
            throw URLError(.badServerResponse)
        }
        
        // Match response based on URL path
        for (pattern, data) in responses {
            if url.path.contains(pattern) {
                return data
            }
        }
    
        throw URLError(.resourceUnavailable)
    }
}

// MARK: - DiscogsAPIEntityResolver Caching Tests

@Suite("DiscogsAPIEntityResolver Caching Tests")
struct DiscogsAPIEntityResolverCachingTests {
    
    @Test("resolveArtist returns cached name without API call")
    func resolveArtistReturnsCached() async throws {
        // Given
        let mockCache = EntityResolverMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = EntityResolverMockWebSession()
        let resolver = DiscogsAPIEntityResolver(session: mockSession, cache: cache)
        
        // Pre-populate cache with artist name
        await cache.set(value: "Cached Artist Name", for: "discogs-artist-12345", lifespan: 3600)
        mockCache.getCallCount = 0  // Reset after setup
        
        // When
        let result = try await resolver.resolveArtist(id: 12345)
        
        // Then
        #expect(result == "Cached Artist Name")
        #expect(mockSession.requestCount == 0, "Should not make API call when cached")
    }
    
    @Test("resolveArtist fetches from API and caches on miss")
    func resolveArtistFetchesAndCaches() async throws {
        // Given
        let mockCache = EntityResolverMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = EntityResolverMockWebSession()
        let resolver = DiscogsAPIEntityResolver(session: mockSession, cache: cache)
        
        // Mock API response
        let artistResponse = """
        {
            "id": 99999,
            "name": "New Artist From API"
        }
        """.data(using: .utf8)!
        mockSession.responses["/artists/99999"] = artistResponse
    
        // When
        let result = try await resolver.resolveArtist(id: 99999)
        
        // Then
        #expect(result == "New Artist From API")
        #expect(mockSession.requestCount == 1, "Should make exactly one API call")
        #expect(mockCache.keysSet.contains("discogs-artist-99999"), "Should cache the result")
    }
    
    @Test("resolveRelease returns cached title without API call")
    func resolveReleaseReturnsCached() async throws {
        // Given
        let mockCache = EntityResolverMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = EntityResolverMockWebSession()
        let resolver = DiscogsAPIEntityResolver(session: mockSession, cache: cache)
        
        // Pre-populate cache
        await cache.set(value: "Cached Album Title", for: "discogs-release-54321", lifespan: 3600)
        mockCache.getCallCount = 0
        
        // When
        let result = try await resolver.resolveRelease(id: 54321)
        
        // Then
        #expect(result == "Cached Album Title")
        #expect(mockSession.requestCount == 0)
    }
    
    @Test("resolveRelease fetches from API and caches on miss")
    func resolveReleaseFetchesAndCaches() async throws {
        // Given
        let mockCache = EntityResolverMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = EntityResolverMockWebSession()
        let resolver = DiscogsAPIEntityResolver(session: mockSession, cache: cache)
        
        // Mock API response
        let releaseResponse = """
        {
            "id": 88888,
            "title": "New Album From API"
        }
        """.data(using: .utf8)!
        mockSession.responses["/releases/88888"] = releaseResponse
    
        // When
        let result = try await resolver.resolveRelease(id: 88888)
        
        // Then
        #expect(result == "New Album From API")
        #expect(mockSession.requestCount == 1)
        #expect(mockCache.keysSet.contains("discogs-release-88888"))
    }
    
    @Test("resolveMaster returns cached title without API call")
    func resolveMasterReturnsCached() async throws {
        // Given
        let mockCache = EntityResolverMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = EntityResolverMockWebSession()
        let resolver = DiscogsAPIEntityResolver(session: mockSession, cache: cache)
        
        // Pre-populate cache
        await cache.set(value: "Cached Master Title", for: "discogs-master-11111", lifespan: 3600)
        mockCache.getCallCount = 0
        
        // When
        let result = try await resolver.resolveMaster(id: 11111)
        
        // Then
        #expect(result == "Cached Master Title")
        #expect(mockSession.requestCount == 0)
    }
    
    @Test("resolveMaster fetches from API and caches on miss")
    func resolveMasterFetchesAndCaches() async throws {
        // Given
        let mockCache = EntityResolverMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = EntityResolverMockWebSession()
        let resolver = DiscogsAPIEntityResolver(session: mockSession, cache: cache)
        
        // Mock API response
        let masterResponse = """
        {
            "id": 77777,
            "title": "New Master From API"
        }
        """.data(using: .utf8)!
        mockSession.responses["/masters/77777"] = masterResponse
    
        // When
        let result = try await resolver.resolveMaster(id: 77777)
        
        // Then
        #expect(result == "New Master From API")
        #expect(mockSession.requestCount == 1)
        #expect(mockCache.keysSet.contains("discogs-master-77777"))
    }
    
    @Test("Second call returns cached result without additional API call")
    func secondCallReturnsCached() async throws {
        // Given
        let mockCache = EntityResolverMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = EntityResolverMockWebSession()
        let resolver = DiscogsAPIEntityResolver(session: mockSession, cache: cache)
        
        // Mock API response
        let artistResponse = """
        {
            "id": 33333,
            "name": "Test Artist"
        }
        """.data(using: .utf8)!
        mockSession.responses["/artists/33333"] = artistResponse
        
        // When - first call
        let result1 = try await resolver.resolveArtist(id: 33333)
        let firstCallCount = mockSession.requestCount
        
        // When - second call
        let result2 = try await resolver.resolveArtist(id: 33333)
        let secondCallCount = mockSession.requestCount
        
        // Then
        #expect(result1 == "Test Artist")
        #expect(result2 == "Test Artist")
        #expect(firstCallCount == 1)
        #expect(secondCallCount == 1, "Second call should use cache, not make another API call")
    }
    
    @Test("Uses correct cache key format for each entity type")
    func usesCorrectCacheKeyFormat() async throws {
        // Given
        let mockCache = EntityResolverMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = EntityResolverMockWebSession()
        let resolver = DiscogsAPIEntityResolver(session: mockSession, cache: cache)
        
        // Mock responses
        mockSession.responses["/artists/1"] = #"{"id": 1, "name": "A"}"#.data(using: .utf8)!
        mockSession.responses["/releases/2"] = #"{"id": 2, "title": "R"}"#.data(using: .utf8)!
        mockSession.responses["/masters/3"] = #"{"id": 3, "title": "M"}"#.data(using: .utf8)!
        
        // When
        _ = try await resolver.resolveArtist(id: 1)
        _ = try await resolver.resolveRelease(id: 2)
        _ = try await resolver.resolveMaster(id: 3)

        // Then
        #expect(mockCache.keysSet.contains("discogs-artist-1"))
        #expect(mockCache.keysSet.contains("discogs-release-2"))
        #expect(mockCache.keysSet.contains("discogs-master-3"))
    }
}
