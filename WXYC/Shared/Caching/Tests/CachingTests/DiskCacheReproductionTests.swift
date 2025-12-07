import Testing
import Foundation
@testable import Caching

/// Tests for CacheCoordinator behavior when encountering corrupted or problematic cache data.
///
/// These tests verify:
/// 1. When `value(for:)` fails to decode cached data, it throws but does NOT delete the entry
/// 2. When `purgeExpiredEntries()` runs (at CacheCoordinator init), it deletes expired entries
/// 3. Type mismatch scenarios are handled correctly
@Suite("DiskCache Corruption Handling Tests")
@MainActor
struct DiskCacheReproductionTests {
    
    // MARK: - Test that value(for:) does NOT delete entries on decode failure
    
    @Test("Corrupted data causes decode failure but entry is not deleted")
    func corruptedDataPersistsAfterDecodeFailure() async throws {
        // Given: A mock cache with corrupted data (valid metadata, invalid JSON payload)
        let mockCache = MockCache()
        let key = "corrupted_playlist"
        
        // Write invalid JSON directly to the cache with valid metadata
        let corruptedData = "Not valid JSON".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)
        mockCache.set(corruptedData, metadata: metadata, for: key)
        
        // Create coordinator
        let coordinator = CacheCoordinator(cache: mockCache)
        
        // Wait for any async purge to complete
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify the corrupted data is in the cache
        #expect(mockCache.data(for: key) != nil)
        
        // When: Try to read the corrupted value
        await #expect(throws: (any Error).self) {
            let _: String = try await coordinator.value(for: key)
        }
        
        // Then: The corrupted entry should STILL be in the cache
        // (value(for:) throws but does NOT delete on decode failure)
        #expect(mockCache.data(for: key) != nil, "Corrupted entry should persist after decode failure")
    }
    
    @Test("Corrupted data causes repeated failures on subsequent reads")
    func corruptedDataCausesRepeatedFailures() async throws {
        // Given: A mock cache with corrupted data
        let mockCache = MockCache()
        let key = "persistent_corruption"
        let corruptedData = "{ invalid json }".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)
        
        let coordinator = CacheCoordinator(cache: mockCache)
        try await Task.sleep(for: .milliseconds(100))
        
        // Write corrupted data after init
        mockCache.set(corruptedData, metadata: metadata, for: key)
        
        // When: Try to read multiple times
        for _ in 0..<3 {
            await #expect(throws: (any Error).self) {
                let _: String = try await coordinator.value(for: key)
            }
        }
        
        // Then: Entry still persists
        #expect(mockCache.data(for: key) != nil, "Corrupted entry persists across multiple read attempts")
    }
    
    // MARK: - Test that purgeExpiredEntries() deletes expired entries
    
    @Test("purgeExpiredEntries deletes expired entries on coordinator initialization")
    func purgeExpiredEntriesDeletesExpiredEntries() async throws {
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
        _ = CacheCoordinator(cache: mockCache)
        
        // Wait for async purge to complete
        try await Task.sleep(for: .milliseconds(200))
        
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
        try await Task.sleep(for: .milliseconds(200))
        
        // Then: Valid entry preserved, expired entry deleted
        #expect(mockCache.data(for: validKey) != nil, "Valid entry should be preserved")
        #expect(mockCache.data(for: expiredKey) == nil, "Expired entry should be deleted")
        
        // And we can still read the valid entry
        let retrieved: String = try await coordinator.value(for: validKey)
        #expect(retrieved == "Hello")
    }
    
    // MARK: - Test type mismatch scenario (stored as one type, read as another)
    
    @Test("Type mismatch throws but does not delete entry")
    func typeMismatchDoesNotDeleteEntry() async throws {
        // Given: Store a value as String
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "type_mismatch"
        
        await coordinator.set(value: "Not a number", for: key, lifespan: 3600)
        
        // Verify it's stored
        #expect(mockCache.data(for: key) != nil)
        
        // When: Try to read as Int (type mismatch)
        await #expect(throws: (any Error).self) {
            let _: Int = try await coordinator.value(for: key)
        }
        
        // Then: Entry should still exist (we might want to read it as String later)
        #expect(mockCache.data(for: key) != nil, "Entry should persist after type mismatch error")
        
        // And we CAN read it as the correct type
        let retrieved: String = try await coordinator.value(for: key)
        #expect(retrieved == "Not a number")
    }
}

