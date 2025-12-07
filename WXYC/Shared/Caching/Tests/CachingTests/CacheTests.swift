/*
 CacheTests.swift

 Comprehensive unit tests for Cache protocol implementations

 Test Coverage:
 - UserDefaultsCache: data storage, retrieval, metadata, and removal
 - DiskCache: disk-based storage with xattr metadata
 - File system operations (creation, reading, deletion)
 - All metadata enumeration
 - Error scenarios and edge cases

 Dependencies:
 - Real FileManager for disk operations (isolated to test cache directory)
 - Temporary test suite names for UserDefaults isolation
 */

import Testing
import Foundation
@testable import Caching

// MARK: - UserDefaultsCache Tests

@Suite("UserDefaultsCache Tests")
struct UserDefaultsCacheTests {

    @Test("Stores and retrieves data")
    func storesAndRetrievesData() async throws {
        // Given
        let cache = UserDefaultsCache()
        let testData = "Hello, World!".data(using: .utf8)!
        let key = "test-key-\(UUID().uuidString)"
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(testData, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == testData)

        // Cleanup
        cache.remove(for: key)
    }

    @Test("Returns nil for non-existent key")
    func returnsNilForNonExistentKey() async throws {
        // Given
        let cache = UserDefaultsCache()
        let key = "non-existent-\(UUID().uuidString)"

        // When
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == nil)
    }

    @Test("Overwrites existing data")
    func overwritesExistingData() async throws {
        // Given
        let cache = UserDefaultsCache()
        let key = "overwrite-key-\(UUID().uuidString)"
        let initialData = "Initial".data(using: .utf8)!
        let updatedData = "Updated".data(using: .utf8)!
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

    @Test("Removes data correctly")
    func removesDataCorrectly() async throws {
        // Given
        let cache = UserDefaultsCache()
        let key = "remove-key-\(UUID().uuidString)"
        let testData = "To be removed".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(testData, metadata: metadata, for: key)
        #expect(cache.data(for: key) != nil)

        cache.remove(for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == nil)
    }

    @Test("allMetadata returns empty array")
    func allMetadataReturnsEmpty() async throws {
        // Given
        let cache = UserDefaultsCache()

        // When
        let records = cache.allMetadata()

        // Then
        #expect(records.isEmpty)
    }

    @Test("Handles empty data")
    func handlesEmptyData() async throws {
        // Given
        let cache = UserDefaultsCache()
        let key = "empty-data-\(UUID().uuidString)"
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
    
    @Test("Stores and retrieves metadata")
    func storesAndRetrievesMetadata() async throws {
        // Given
        let cache = UserDefaultsCache()
        let key = "metadata-key-\(UUID().uuidString)"
        let testData = "Test".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 7200)

        // When
        cache.set(testData, metadata: metadata, for: key)
        let retrieved = cache.metadata(for: key)

        // Then
        #expect(retrieved != nil)
        #expect(retrieved?.lifespan == 7200)

        // Cleanup
        cache.remove(for: key)
    }
}

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

    @Test("UserDefaultsCache conforms to Cache protocol")
    func userDefaultsCacheConformance() async throws {
        // Given
        let cache: any Cache = UserDefaultsCache()
        let key = "protocol-test-\(UUID().uuidString)"
        let data = "Protocol test".data(using: .utf8)!
        let metadata = CacheMetadata(lifespan: 3600)

        // When
        cache.set(data, metadata: metadata, for: key)
        let retrieved = cache.data(for: key)

        // Then
        #expect(retrieved == data)

        // Cleanup
        cache.remove(for: key)
    }

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
