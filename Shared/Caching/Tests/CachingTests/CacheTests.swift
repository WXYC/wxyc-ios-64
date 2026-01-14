//
//  CacheTests.swift
//  Caching
//
//  Tests for DiskCache file operations and xattr metadata storage.
//
//  Created by Jake Bromberg on 11/11/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

/*
 CacheTests.swift

 Comprehensive unit tests for Cache protocol implementations

 Test Coverage:
 - DiskCache: disk-based storage with xattr metadata
 - File system operations (creation, reading, deletion)
 - All metadata enumeration
 - Error scenarios and edge cases

 Dependencies:
 - Real FileManager for disk operations (isolated to test cache directory)
 */

import Testing
import Foundation
@testable import Caching

// MARK: - DiskCache Tests

@Suite("DiskCache Tests")
struct DiskCacheTests {

    @Test("Stores and retrieves data from disk")
    func storesAndRetrievesDataFromDisk() async throws {
        // Given
        let cache = DiskCache()
        let testData = "Disk Cache Test".data(using: .utf8)!
        let key = "disk-test-\(UUID().uuidString)"
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(testData, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == testData)

        // Cleanup
        cache.remove(for: key)
    }

    @Test("Returns nil for non-existent file")
    func returnsNilForNonExistentFile() async throws {
        // Given
        let cache = DiskCache()
        let key = "non-existent-file-\(UUID().uuidString)"

        // When
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == nil)
    }

    @Test("Deletes file when removed")
    func deletesFileWhenRemoved() async throws {
        // Given
        let cache = DiskCache()
        let key = "delete-test-\(UUID().uuidString)"
        let testData = "Will be deleted".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(testData, metadata: metadata, for: key)
        #expect(cache.data(for: key) != nil)

        cache.remove(for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == nil)
    }

    @Test("Handles large data")
    func handlesLargeData() async throws {
        // Given
        let cache = DiskCache()
        let key = "large-data-\(UUID().uuidString)"
        // Create 1MB of data
        let largeData = Data(repeating: 0xFF, count: 1024 * 1024)
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(largeData, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == largeData)

        // Cleanup
        cache.remove(for: key)
    }

    @Test("Handles special characters in key")
    func handlesSpecialCharactersInKey() async throws {
        // Given
        let cache = DiskCache()
        // Use URL-safe characters
        let key = "special-key_with-chars.123-\(UUID().uuidString)"
        let testData = "Special key test".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(testData, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == testData)

        // Cleanup
        cache.remove(for: key)
    }

    @Test("Overwrites existing file")
    func overwritesExistingFile() async throws {
        // Given
        let cache = DiskCache()
        let key = "overwrite-file-\(UUID().uuidString)"
        let initialData = "Initial content".data(using: .utf8)!
        let updatedData = "Updated content".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(initialData, metadata: metadata, for: key)
        cache.set(updatedData, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)
    
        // Then
        #expect(retrieved == updatedData)

        // Cleanup
        cache.remove(for: key)
    }

    @Test("Handles binary data")
    func handlesBinaryData() async throws {
        // Given
        let cache = DiskCache()
        let key = "binary-test-\(UUID().uuidString)"
        var binaryData = Data()
        for byte in 0..<256 {
            binaryData.append(UInt8(byte))
        }
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(binaryData, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == binaryData)

        // Cleanup
        cache.remove(for: key)
    }

    @Test("Handles concurrent access")
    func handlesConcurrentAccess() async throws {
        // Given
        let cache = DiskCache()
        let keys = (0..<10).map { "concurrent-\($0)-\(UUID().uuidString)" }
        let metadata = CacheMetadata(lifespan: 3600)

        // When - Write concurrently
        await withTaskGroup(of: Void.self) { group in
            for (index, key) in keys.enumerated() {
                group.addTask {
                    let data = "Data \(index)".data(using: .utf8)!
                    cache.set(data, metadata: metadata, for: key)
                }
            }
        }

        // Then - All should be readable
        for (index, key) in keys.enumerated() {
            let retrieved = cache.data(for: key)
            let expected = "Data \(index)".data(using: .utf8)!
            #expect(retrieved == expected)
        }

        // Cleanup
        for key in keys {
            cache.remove(for: key)
        }
    }

    @Test("Handles empty data")
    func handlesEmptyData() async throws {
        // Given
        let cache = DiskCache()
        let key = "empty-disk-\(UUID().uuidString)"
        let emptyData = Data()
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(emptyData, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == emptyData)

        // Cleanup
        cache.remove(for: key)
    }

    @Test("Stores and retrieves metadata via xattr")
    func storesAndRetrievesMetadataViaXattr() async throws {
        // Given
        let cache = DiskCache()
        let key = "xattr-test-\(UUID().uuidString)"
        let testData = "Test".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 7200)

        // When
        cache.set(testData, metadata: metadata, for: key)
        let retrievedMetadata = cache.metadata(for: key)
    
        // Then
        #expect(retrievedMetadata != nil)
        #expect(retrievedMetadata?.lifespan == 7200)

        // Cleanup
        cache.remove(for: key)
    }
    
    @Test("allMetadata returns stored entries")
    func allMetadataReturnsStoredEntries() async throws {
        // Given
        let cache = DiskCache()
        let key1 = "allmetadata-test-1-\(UUID().uuidString)"
        let key2 = "allmetadata-test-2-\(UUID().uuidString)"
        let data = "Test".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(data, metadata: metadata, for: key1)
        cache.set(data, metadata: metadata, for: key2)
        
        let allEntries = cache.allMetadata()
        let keys = allEntries.map { $0.key }

        // Then
        #expect(keys.contains(key1))
        #expect(keys.contains(key2))

        // Cleanup
        cache.remove(for: key1)
        cache.remove(for: key2)
    }

    @Test("Purges old-format files without xattr")
    func purgesOldFormatFilesWithoutXattr() async throws {
        // Given - Create a file directly without xattr (simulating old format)
        let cache = DiskCache()
        let key = "old-format-\(UUID().uuidString)"
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = cacheDirectory.appendingPathComponent(key)

        // Write file directly without xattr
        let data = "Old format data".data(using: .utf8)!
        FileManager.default.createFile(atPath: fileURL.path, contents: data)
        
        // Verify file exists
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // When - Try to read via cache (should purge old format)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}

// MARK: - Cache Protocol Conformance Tests

@Suite("Cache Protocol Conformance")
struct CacheProtocolTests {

    @Test("DiskCache conforms to Cache protocol")
    func diskCacheConformance() async throws {
        // Given
        let cache: any Cache = DiskCache()
        let key = "protocol-disk-\(UUID().uuidString)"
        let data = "Protocol disk test".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(data, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == data)

        // Cleanup
        cache.remove(for: key)
    }
}

// MARK: - DiskCache Integration Tests

@Suite("DiskCache Expiration Integration Tests")
struct DiskCacheExpirationIntegrationTests {

    @Test("Expired data retrieval returns nil and deletes file from disk")
    func expiredDataRetrievalReturnsNilAndDeletesFile() async throws {
        // Given: A real DiskCache with a controllable clock
        let diskCache = DiskCache()
        let mockClock = MockClock()
        let coordinator = CacheCoordinator(cache: diskCache, clock: mockClock)
        await coordinator.waitForPurge()

        let key = "expiration-integration-\(UUID().uuidString)"
        let value = "Will expire soon"

        // Store data with 60 second lifespan
        await coordinator.set(value: value, for: key, lifespan: 60)

        // Verify file exists on disk
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = cacheDirectory.appendingPathComponent(key)
        #expect(FileManager.default.fileExists(atPath: fileURL.path), "File should exist after storing")

        // When: Advance clock past expiration and try to retrieve
        mockClock.advance(by: 61)

        // Then: Should throw noCachedResult
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: String = try await coordinator.value(for: key)
        }

        // And: File should be deleted from disk
        #expect(!FileManager.default.fileExists(atPath: fileURL.path), "File should be deleted after expired retrieval")
    }

    @Test("Expired binary data retrieval returns nil and deletes file from disk")
    func expiredBinaryDataRetrievalReturnsNilAndDeletesFile() async throws {
        // Given: A real DiskCache with a controllable clock
        let diskCache = DiskCache()
        let mockClock = MockClock()
        let coordinator = CacheCoordinator(cache: diskCache, clock: mockClock)
        await coordinator.waitForPurge()

        let key = "binary-expiration-\(UUID().uuidString)"
        let data = Data(repeating: 0xAB, count: 1024)

        // Store binary data with 60 second lifespan
        await coordinator.setData(data, for: key, lifespan: 60)

        // Verify file exists on disk
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = cacheDirectory.appendingPathComponent(key)
        #expect(FileManager.default.fileExists(atPath: fileURL.path), "File should exist after storing")

        // When: Advance clock past expiration and try to retrieve
        mockClock.advance(by: 61)

        // Then: Should throw noCachedResult
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            _ = try await coordinator.data(for: key)
        }

        // And: File should be deleted from disk
        #expect(!FileManager.default.fileExists(atPath: fileURL.path), "File should be deleted after expired retrieval")
    }
}
