//
//  DiskCacheReproductionTests.swift
//  Caching
//
//  Tests for cache behavior with corrupted or problematic data.
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Caching

/// Tests for CacheCoordinator behavior when encountering corrupted or problematic cache data.
///
/// These tests verify:
/// 1. When `value(for:)` fails to decode cached data, it evicts the corrupt entry and throws
/// 2. When `purgeExpiredEntries()` runs (at CacheCoordinator init), it deletes expired entries
/// 3. Type mismatch scenarios evict the mismatched entry
@Suite("DiskCache Corruption Handling Tests")
@MainActor
struct DiskCacheReproductionTests {
    
    // MARK: - Test that value(for:) evicts entries on decode failure
    //
    // Corrupt cache entries are evicted on first read failure to prevent repeated
    // Sentry events from the same stale data. This is especially important after
    // schema changes (e.g., adding a required field to a Codable type) where old
    // cached data would fail on every access until TTL expiry.

    @Test("Corrupted data is evicted on decode failure")
    func corruptedDataIsEvictedOnDecodeFailure() async {
        // Given: A mock cache with corrupted data (valid metadata, invalid JSON payload)
        let mockCache = MockCache()
        let key = "corrupted_playlist"

        // Write invalid JSON directly to the cache with valid metadata
        let corruptedData = "Not valid JSON".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)
        mockCache.set(corruptedData, metadata: metadata, for: key)

        // Create coordinator
        let coordinator = CacheCoordinator(cache: mockCache)

        // Wait for initial purge to complete
        await coordinator.waitForPurge()

        // Verify the corrupted data is in the cache
        #expect(mockCache.data(for: key) != nil)

        // When: Try to read the corrupted value
        await #expect(throws: (any Error).self) {
            let _: String = try await coordinator.value(for: key)
        }

        // Then: The corrupted entry should be evicted
        #expect(mockCache.data(for: key) == nil, "Corrupted entry should be evicted on decode failure")
    }

    @Test("Second read after eviction throws noCachedResult instead of decode error")
    func secondReadAfterEvictionThrowsNoCachedResult() async {
        // Given: A mock cache with corrupted data
        let mockCache = MockCache()
        let key = "persistent_corruption"
        let corruptedData = "{ invalid json }".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)

        let coordinator = CacheCoordinator(cache: mockCache)
        await coordinator.waitForPurge()

        // Write corrupted data after init
        mockCache.set(corruptedData, metadata: metadata, for: key)

        // First read: throws DecodingError and evicts
        await #expect(throws: (any Error).self) {
            let _: String = try await coordinator.value(for: key)
        }

        // Second read: entry is gone, throws noCachedResult
        await #expect(throws: CacheCoordinator.Error.self) {
            let _: String = try await coordinator.value(for: key)
        }
    }
    
    // MARK: - Test that purgeExpiredEntries() deletes expired entries
    
    @Test("purgeExpiredEntries deletes expired entries on coordinator initialization")
    func purgeExpiredEntriesDeletesExpiredEntries() async {
        // Given: A mock cache pre-populated with expired data
        let mockCache = MockCache()
        let expiredKey = "expired_on_init"
        let expiredData = "some data".data(using: .utf8)!
        
        // Create metadata that is already expired
        let expiredMetadata = CacheMetadata(
            timestamp: Date.timeIntervalSinceReferenceDate - 7200, // 2 hours ago
            lifespan: 3600 // 1 hour lifespan
        )
        mockCache.set(expiredData, metadata: expiredMetadata, for: expiredKey)
        
        // Verify expired data is present
        #expect(mockCache.data(for: expiredKey) != nil)
    
        // When: Create a new CacheCoordinator (which calls purgeExpiredEntries in init)
        let coordinator = CacheCoordinator(cache: mockCache)
        await coordinator.waitForPurge()

        // Then: The expired entry should be deleted by purgeExpiredEntries
        #expect(mockCache.data(for: expiredKey) == nil, "purgeExpiredEntries should delete expired entries")
    }
    
    @Test("purgeExpiredEntries preserves valid entries while deleting expired ones")
    func purgeExpiredEntriesPreservesValidEntries() async throws {
        // Given: A cache with both valid and expired entries
        let mockCache = MockCache()
        let validKey = "valid_entry"
        let expiredKey = "expired_entry"
        
        // Create valid entry with fresh metadata
        let validData = try JSONEncoder().encode("Hello")
        let validMetadata = CacheMetadata(lifespan: 3600)
        mockCache.set(validData, metadata: validMetadata, for: validKey)
        
        // Create expired entry
        let expiredData = "expired data".data(using: .utf8)!
        let expiredMetadata = CacheMetadata(
            timestamp: Date.timeIntervalSinceReferenceDate - 7200,
            lifespan: 3600
        )
        mockCache.set(expiredData, metadata: expiredMetadata, for: expiredKey)
        
        // Verify both are present
        #expect(mockCache.data(for: validKey) != nil)
        #expect(mockCache.data(for: expiredKey) != nil)
        
        // When: Create coordinator (triggers purgeExpiredEntries)
        let coordinator = CacheCoordinator(cache: mockCache)
        await coordinator.waitForPurge()
        
        // Then: Valid entry preserved, expired entry deleted
        #expect(mockCache.data(for: validKey) != nil, "Valid entry should be preserved")
        #expect(mockCache.data(for: expiredKey) == nil, "Expired entry should be deleted")
        
        // And we can still read the valid entry
        let retrieved: String = try await coordinator.value(for: validKey)
        #expect(retrieved == "Hello")
    }
    
    // MARK: - Test type mismatch scenario (stored as one type, read as another)
    
    @Test("Type mismatch evicts entry since it produces a DecodingError")
    func typeMismatchEvictsEntry() async throws {
        // Given: Store a value as String
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "type_mismatch"

        await coordinator.set(value: "Not a number", for: key, lifespan: 3600)

        // Verify it's stored
        #expect(mockCache.data(for: key) != nil)

        // When: Try to read as Int (type mismatch → DecodingError)
        await #expect(throws: (any Error).self) {
            let _: Int = try await coordinator.value(for: key)
        }

        // Then: Entry is evicted because type mismatch produces a DecodingError
        #expect(mockCache.data(for: key) == nil, "Entry should be evicted after type mismatch (DecodingError)")
    }
}
