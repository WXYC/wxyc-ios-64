import Testing
import Foundation
@testable import Caching

/// Tests for CacheCoordinator behavior when encountering corrupted cache data.
///
/// These tests verify:
/// 1. When `value(for:)` fails to decode cached data, it throws but does NOT delete the entry
/// 2. When `purgeRecords()` runs (at CacheCoordinator init), it DOES delete corrupted entries
/// 3. Corrupted entries persist across multiple `value(for:)` calls within a session
@Suite("DiskCache Corruption Handling Tests")
@MainActor
struct DiskCacheReproductionTests {
    
    // MARK: - Test that value(for:) does NOT delete corrupted entries
    
    @Test("Corrupted data causes decode failure but entry is not deleted")
    func corruptedDataPersistsAfterDecodeFailure() async throws {
        // Given: A mock cache with corrupted data
        let mockCache = MockCache()
        let key = "corrupted_playlist"
        
        // Write invalid JSON directly to the cache (simulating corruption)
        let corruptedData = "Not valid JSON for CachedRecord<String>".data(using: .utf8)!
        mockCache.set(object: corruptedData, for: key)
        
        // Create coordinator WITHOUT purging (we'll test purging separately)
        // Note: CacheCoordinator calls purgeRecords() in init, but we can verify
        // the value(for:) behavior by writing AFTER init
        let coordinator = CacheCoordinator(cache: mockCache)
        
        // Wait for any async purge to complete
        try await Task.sleep(for: .milliseconds(100))
        
        // Now write corrupted data AFTER coordinator init (so purgeRecords already ran)
        mockCache.set(object: corruptedData, for: key)
        
        // Verify the corrupted data is in the cache
        #expect(mockCache.object(for: key) != nil)
        
        // When: Try to read the corrupted value
        await #expect(throws: (any Error).self) {
            let _: String = try await coordinator.value(for: key)
        }
        
        // Then: The corrupted entry should STILL be in the cache
        // (value(for:) throws but does NOT delete on decode failure)
        #expect(mockCache.object(for: key) != nil, "Corrupted entry should persist after decode failure")
    }
    
    @Test("Corrupted data causes repeated failures on subsequent reads")
    func corruptedDataCausesRepeatedFailures() async throws {
        // Given: A mock cache with corrupted data
        let mockCache = MockCache()
        let key = "persistent_corruption"
        let corruptedData = "{ invalid json }".data(using: .utf8)!
        
        let coordinator = CacheCoordinator(cache: mockCache)
        try await Task.sleep(for: .milliseconds(100))
        
        // Write corrupted data after init
        mockCache.set(object: corruptedData, for: key)
        
        // When: Try to read multiple times
        for _ in 0..<3 {
            await #expect(throws: (any Error).self) {
                let _: String = try await coordinator.value(for: key)
            }
        }
        
        // Then: Entry still persists (this is the "persistent" symptom from the original comments)
        #expect(mockCache.object(for: key) != nil, "Corrupted entry persists across multiple read attempts")
    }
    
    // MARK: - Test that purgeRecords() DOES delete corrupted entries
    
    @Test("purgeRecords deletes corrupted entries on coordinator initialization")
    func purgeRecordsDeletesCorruptedEntries() async throws {
        // Given: A mock cache pre-populated with corrupted data
        let mockCache = MockCache()
        let corruptedKey = "corrupted_on_init"
        let corruptedData = "garbage data that won't decode".data(using: .utf8)!
        mockCache.set(object: corruptedData, for: corruptedKey)
        
        // Verify corrupted data is present
        #expect(mockCache.object(for: corruptedKey) != nil)
        
        // When: Create a new CacheCoordinator (which calls purgeRecords in init)
        _ = CacheCoordinator(cache: mockCache)
        
        // Wait for async purgeRecords to complete
        try await Task.sleep(for: .milliseconds(200))
        
        // Then: The corrupted entry should be deleted by purgeRecords
        #expect(mockCache.object(for: corruptedKey) == nil, "purgeRecords should delete corrupted entries")
    }
    
    @Test("purgeRecords preserves valid entries while deleting corrupted ones")
    func purgeRecordsPreservesValidEntries() async throws {
        // Given: A cache with both valid and corrupted entries
        let mockCache = MockCache()
        let validKey = "valid_entry"
        let corruptedKey = "corrupted_entry"
        
        // Create valid CachedRecord data
        let validRecord = CachedRecord(value: "Hello", lifespan: 3600)
        let validData = try JSONEncoder().encode(validRecord)
        mockCache.set(object: validData, for: validKey)
        
        // Create corrupted data
        let corruptedData = "not a cached record".data(using: .utf8)!
        mockCache.set(object: corruptedData, for: corruptedKey)
        
        // Verify both are present
        #expect(mockCache.object(for: validKey) != nil)
        #expect(mockCache.object(for: corruptedKey) != nil)
        
        // When: Create coordinator (triggers purgeRecords)
        let coordinator = CacheCoordinator(cache: mockCache)
        try await Task.sleep(for: .milliseconds(200))
        
        // Then: Valid entry preserved, corrupted entry deleted
        #expect(mockCache.object(for: validKey) != nil, "Valid entry should be preserved")
        #expect(mockCache.object(for: corruptedKey) == nil, "Corrupted entry should be deleted")
        
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
        #expect(mockCache.object(for: key) != nil)
        
        // When: Try to read as Int (type mismatch)
        await #expect(throws: (any Error).self) {
            let _: Int = try await coordinator.value(for: key)
        }
        
        // Then: Entry should still exist (we might want to read it as String later)
        #expect(mockCache.object(for: key) != nil, "Entry should persist after type mismatch error")
        
        // And we CAN read it as the correct type
        let retrieved: String = try await coordinator.value(for: key)
        #expect(retrieved == "Not a number")
    }
}

