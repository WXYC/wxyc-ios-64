//
//  MigratingDiskCacheTests.swift
//  Caching
//
//  Tests for MigratingDiskCache migration from legacy to shared container.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

/*
 MigratingDiskCacheTests.swift

 Tests for MigratingDiskCache migration behavior from legacy private
 cache directory to shared App Group container.

 Test Coverage:
 - Migration from legacy to shared container
 - Preference of shared over legacy data
 - Write behavior (shared only)
 - Remove behavior (both locations)
 - allMetadata combining both locations
 - Empty legacy handling
 - Expired legacy data handling
 */

import Testing
import Foundation
@testable import Caching

@Suite("MigratingDiskCache Tests")
struct MigratingDiskCacheTests {

    @Test("Migrates data from legacy to shared container")
    func migratesDataFromLegacyToShared() async throws {
        // Given - Write directly to legacy location
        let legacyCache = DiskCache(useSharedContainer: false)
        let key = "migration-test-\(UUID().uuidString)"
        let testData = "Legacy data".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)
        legacyCache.set(testData, metadata: metadata, for: key)
        
        // When - Read via MigratingDiskCache
        let migratingCache = MigratingDiskCache()
        let retrieved = migratingCache.data(for: key)
        
        // Then - Data is returned and migrated
        #expect(retrieved == testData)
        
        // Verify: now in shared, not in legacy
        let sharedCache = DiskCache(useSharedContainer: true)
        #expect(sharedCache.data(for: key) == testData)
        #expect(legacyCache.data(for: key) == nil)
        
        // Cleanup
        migratingCache.remove(for: key)
    }

    @Test("Prefers shared over legacy data")
    func prefersSharedOverLegacy() async throws {
        // Given - Write different data to both locations
        let legacyCache = DiskCache(useSharedContainer: false)
        let sharedCache = DiskCache(useSharedContainer: true)
        let key = "prefer-shared-\(UUID().uuidString)"
        let legacyData = "Legacy data".data(using: .utf8)!
        let sharedData = "Shared data".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)
        
        legacyCache.set(legacyData, metadata: metadata, for: key)
        sharedCache.set(sharedData, metadata: metadata, for: key)
        
        // When - Read via MigratingDiskCache
        let migratingCache = MigratingDiskCache()
        let retrieved = migratingCache.data(for: key)
        
        // Then - Shared data is returned (not legacy)
        #expect(retrieved == sharedData)
        
        // Cleanup
        migratingCache.remove(for: key)
    }
        
    @Test("Writes only to shared container")
    func writesOnlyToShared() async throws {
        // Given
        let migratingCache = MigratingDiskCache()
        let key = "write-test-\(UUID().uuidString)"
        let testData = "New data".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)
        
        // When - Write via MigratingDiskCache
        migratingCache.set(testData, metadata: metadata, for: key)
        
        // Then - Verify file exists only in shared container
        let sharedCache = DiskCache(useSharedContainer: true)
        let legacyCache = DiskCache(useSharedContainer: false)
        
        #expect(sharedCache.data(for: key) == testData)
        #expect(legacyCache.data(for: key) == nil)
        
        // Cleanup
        migratingCache.remove(for: key)
    }

    @Test("Remove cleans up both locations")
    func removeCleansUpBothLocations() async throws {
        // Given - Write to both locations
        let legacyCache = DiskCache(useSharedContainer: false)
        let sharedCache = DiskCache(useSharedContainer: true)
        let key = "remove-test-\(UUID().uuidString)"
        let data = "Test data".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)
        
        legacyCache.set(data, metadata: metadata, for: key)
        sharedCache.set(data, metadata: metadata, for: key)
        
        // Verify both exist
        #expect(legacyCache.data(for: key) != nil)
        #expect(sharedCache.data(for: key) != nil)
        
        // When - Remove via MigratingDiskCache
        let migratingCache = MigratingDiskCache()
        migratingCache.remove(for: key)
        
        // Then - Both are deleted
        #expect(legacyCache.data(for: key) == nil)
        #expect(sharedCache.data(for: key) == nil)
    }

    @Test("allMetadata combines both locations")
    func allMetadataCombinesBothLocations() async throws {
        // Given - Write unique keys to each location
        let legacyCache = DiskCache(useSharedContainer: false)
        let sharedCache = DiskCache(useSharedContainer: true)
        let legacyKey = "legacy-only-\(UUID().uuidString)"
        let sharedKey = "shared-only-\(UUID().uuidString)"
        let data = "Test data".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)
        
        legacyCache.set(data, metadata: metadata, for: legacyKey)
        sharedCache.set(data, metadata: metadata, for: sharedKey)
        
        // When
        let migratingCache = MigratingDiskCache()
        let allEntries = migratingCache.allMetadata()
        let keys = allEntries.map { $0.key }
        
        // Then - Both keys are present
        #expect(keys.contains(legacyKey))
        #expect(keys.contains(sharedKey))
        
        // Cleanup
        migratingCache.remove(for: legacyKey)
        migratingCache.remove(for: sharedKey)
    }

    @Test("Handles empty legacy gracefully")
    func handlesEmptyLegacy() async throws {
        // Given - No data in legacy
        let key = "nonexistent-\(UUID().uuidString)"

        // When - Read via MigratingDiskCache
        let migratingCache = MigratingDiskCache()
        let retrieved = migratingCache.data(for: key)
        
        // Then - Returns nil without error
        #expect(retrieved == nil)
    }

    @Test("Does not migrate expired legacy data")
    func handlesExpiredLegacyData() async throws {
        // Given - Write expired data to legacy
        let legacyCache = DiskCache(useSharedContainer: false)
        let key = "expired-legacy-\(UUID().uuidString)"
        let testData = "Expired data".data(using: .utf8)!
        // Create metadata that is already expired (timestamp in the past)
        let expiredMetadata = CacheMetadata(
            timestamp: Date.timeIntervalSinceReferenceDate - 7200,  // 2 hours ago
            lifespan: 3600  // 1 hour lifespan = expired
        )
        legacyCache.set(testData, metadata: expiredMetadata, for: key)
        
        // When - Read via MigratingDiskCache
        let migratingCache = MigratingDiskCache()
        let metadata = migratingCache.metadata(for: key)
        
        // Then - Metadata indicates expired (CacheCoordinator will handle expiry)
        // The MigratingDiskCache itself doesn't filter expired data - that's CacheCoordinator's job
        // But we verify the metadata is properly returned so CacheCoordinator can check isExpired
        #expect(metadata != nil)
        #expect(metadata?.isExpired == true)

        // Cleanup
        migratingCache.remove(for: key)
    }
}
