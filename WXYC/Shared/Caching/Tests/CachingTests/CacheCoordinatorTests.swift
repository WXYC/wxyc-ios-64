/*
 CacheCoordinatorTests.swift

 Comprehensive unit tests for CacheCoordinator actor

 Test Coverage:
 - Value storage and retrieval with TTL
 - Expiration handling
 - Error handling for missing/expired values
 - Codable value encoding/decoding
 - Cache purging of expired records
 - Concurrent access via actor isolation
 - Various data types (String, Int, custom structs)

 Dependencies:
 - MockCache for isolated testing without file system dependencies
 - Real Cache implementations for integration tests
 */

import Testing
import Foundation
@testable import Caching

// MARK: - Mock Cache

final class MockCache: Cache, @unchecked Sendable {
    private var dataStorage: [String: Data] = [:]
    private var metadataStorage: [String: CacheMetadata] = [:]
    private let lock = NSLock()

    func metadata(for key: String) -> CacheMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return metadataStorage[key]
    }
    
    func data(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return dataStorage[key]
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data = data {
            dataStorage[key] = data
            metadataStorage[key] = metadata
        } else {
            remove(for: key)
        }
    }
    
    func remove(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        dataStorage.removeValue(forKey: key)
        metadataStorage.removeValue(forKey: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        lock.lock()
        defer { lock.unlock() }
        return metadataStorage.map { ($0.key, $0.value) }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        dataStorage.removeAll()
        metadataStorage.removeAll()
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return dataStorage.count
    }
}

// MARK: - Test Data Types

struct TestPerson: Codable, Equatable {
    let name: String
    let age: Int
}

struct TestLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let name: String
}

// MARK: - CacheCoordinator Tests

@Suite("CacheCoordinator Tests")
@MainActor
struct CacheCoordinatorTests {

    // MARK: - Basic Storage and Retrieval

    @Test("Stores and retrieves string values")
    func storesAndRetrievesStrings() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "test-string"
        let value = "Hello, Cache!"

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: String = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    @Test("Stores and retrieves integer values")
    func storesAndRetrievesIntegers() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "test-int"
        let value = 42

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: Int = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    @Test("Stores and retrieves custom structs")
    func storesAndRetrievesCustomStructs() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "test-person"
        let value = TestPerson(name: "Alice", age: 30)

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: TestPerson = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    @Test("Stores and retrieves arrays")
    func storesAndRetrievesArrays() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "test-array"
        let value = [1, 2, 3, 4, 5]

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: [Int] = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    @Test("Stores and retrieves dictionaries")
    func storesAndRetrievesDictionaries() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "test-dict"
        let value = ["name": "Bob", "city": "NYC"]

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: [String: String] = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    // MARK: - Expiration Tests

    @Test("Throws error for expired values")
    func throwsErrorForExpiredValues() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "expired-value"
        let value = "Will expire"

        // When - Set with very short lifespan
        await coordinator.set(value: value, for: key, lifespan: 0.001)

        // Wait for expiration
        try await Task.sleep(for: .milliseconds(10))

        // Then - Should throw noCachedResult
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: String = try await coordinator.value(for: key)
        }
    }

    @Test("Non-expired values are accessible")
    func nonExpiredValuesAreAccessible() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "valid-value"
        let value = "Still valid"

        // When - Set with long lifespan
        await coordinator.set(value: value, for: key, lifespan: 3600)

        // Wait a bit but not long enough to expire
        try await Task.sleep(for: .milliseconds(50))

        // Then - Should still be retrievable
        let retrieved: String = try await coordinator.value(for: key)
        #expect(retrieved == value)
    }

    @Test("Expired records are removed from cache")
    func expiredRecordsAreRemoved() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "to-be-removed"
        let value = "Remove me"

        // When
        await coordinator.set(value: value, for: key, lifespan: 0.001)

        // Verify it's in cache
        #expect(mockCache.data(for: key) != nil)

        // Wait for expiration
        try await Task.sleep(for: .milliseconds(10))

        // Try to retrieve (which should remove it)
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: String = try await coordinator.value(for: key)
        }

        // Then - Should be removed from underlying cache
        // Give async cleanup time to complete
        try await Task.sleep(for: .milliseconds(50))
        #expect(mockCache.data(for: key) == nil)
    }

    // MARK: - Error Handling

    @Test("Throws error for non-existent key")
    func throwsErrorForNonExistentKey() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "does-not-exist"

        // When/Then
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: String = try await coordinator.value(for: key)
        }
    }

    @Test("Throws error for type mismatch")
    func throwsErrorForTypeMismatch() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "type-mismatch"

        // When - Store as String
        await coordinator.set(value: "Not a number", for: key, lifespan: 3600)

        // Then - Try to retrieve as Int should fail
        await #expect(throws: (any Error).self) {
            let _: Int = try await coordinator.value(for: key)
        }
    }

    // MARK: - Nil Handling

    @Test("Setting nil removes value")
    func settingNilRemovesValue() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "remove-with-nil"
        let value = "To be removed"

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        #expect(mockCache.data(for: key) != nil)

        await coordinator.set(value: nil as String?, for: key, lifespan: 3600)

        // Then
        #expect(mockCache.data(for: key) == nil)

        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: String = try await coordinator.value(for: key)
        }
    }

    // MARK: - Overwriting Values

    @Test("Overwrites existing values")
    func overwritesExistingValues() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "overwrite-test"
        let initialValue = "Initial"
        let updatedValue = "Updated"

        // When
        await coordinator.set(value: initialValue, for: key, lifespan: 3600)
        await coordinator.set(value: updatedValue, for: key, lifespan: 3600)

        let retrieved: String = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == updatedValue)
    }

    @Test("Updates lifespan when overwriting")
    func updatesLifespanWhenOverwriting() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "lifespan-update"
        let value = "Same value"

        // When - First set with short lifespan
        await coordinator.set(value: value, for: key, lifespan: 0.05)

        // Wait almost until expiration
        try await Task.sleep(for: .milliseconds(30))

        // Update with longer lifespan
        await coordinator.set(value: value, for: key, lifespan: 3600)

        // Wait past original expiration
        try await Task.sleep(for: .milliseconds(30))

        // Then - Should still be valid with new lifespan
        let retrieved: String = try await coordinator.value(for: key)
        #expect(retrieved == value)
    }

    // MARK: - Complex Types

    @Test("Handles nested structures")
    func handlesNestedStructures() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "nested-test"
        let value = [
            TestPerson(name: "Alice", age: 30),
            TestPerson(name: "Bob", age: 25)
        ]

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: [TestPerson] = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    @Test("Handles optional values")
    func handlesOptionalValues() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "optional-test"
        let value: String? = "Optional value"

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: String? = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    // MARK: - Concurrent Access

    @Test("Handles concurrent reads and writes")
    func handlesConcurrentReadsAndWrites() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)

        // When - Concurrent writes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let key = "concurrent-\(i)"
                    let value = "Value \(i)"
                    await coordinator.set(value: value, for: key, lifespan: 3600)
                }
            }
        }

        // Then - All should be readable
        for i in 0..<20 {
            let key = "concurrent-\(i)"
            let expected = "Value \(i)"
            let retrieved: String = try await coordinator.value(for: key)
            #expect(retrieved == expected)
        }
    }

    @Test("Actor isolation prevents data races")
    func actorIsolationPreventsDataRaces() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "race-test"

        // When - Multiple concurrent writes to same key
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await coordinator.set(value: i, for: key, lifespan: 3600)
                }
            }
        }

        // Then - Should have one of the values (no crash/corruption)
        let retrieved: Int = try await coordinator.value(for: key)
        #expect(retrieved >= 0 && retrieved < 100)
    }

    // MARK: - Integration Tests with Real Cache

    @Test("Integration with UserDefaultsCache")
    func integrationWithUserDefaultsCache() async throws {
        // Given
        let realCache = UserDefaultsCache()
        let coordinator = CacheCoordinator(cache: realCache)
        let key = "integration-ud-\(UUID().uuidString)"
        let value = TestLocation(latitude: 35.9132, longitude: -79.0558, name: "Chapel Hill")

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: TestLocation = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)

        // Cleanup
        await coordinator.set(value: nil as TestLocation?, for: key, lifespan: 0)
    }

    @Test("Integration with DiskCache")
    func integrationWithDiskCache() async throws {
        // Given
        let realCache = DiskCache()
        let coordinator = CacheCoordinator(cache: realCache)
        let key = "integration-disk-\(UUID().uuidString)"
        let value = ["users": ["alice", "bob", "charlie"]]

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: [String: [String]] = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)

        // Cleanup
        await coordinator.set(value: nil as [String: [String]]?, for: key, lifespan: 0)
    }

    // MARK: - Edge Cases

    @Test("Handles empty strings")
    func handlesEmptyStrings() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "empty-string"
        let value = ""

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: String = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    @Test("Handles zero values")
    func handlesZeroValues() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "zero-value"
        let value = 0

        // When
        await coordinator.set(value: value, for: key, lifespan: 3600)
        let retrieved: Int = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }

    @Test("Handles negative lifespan gracefully")
    func handlesNegativeLifespan() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "negative-lifespan"
        let value = "Already expired"

        // When - Set with negative lifespan (already expired)
        await coordinator.set(value: value, for: key, lifespan: -1)

        // Then - Should be expired immediately
        await #expect(throws: CacheCoordinator.Error.noCachedResult) {
            let _: String = try await coordinator.value(for: key)
        }
    }

    @Test("Handles very large lifespan")
    func handlesVeryLargeLifespan() async throws {
        // Given
        let mockCache = MockCache()
        let coordinator = CacheCoordinator(cache: mockCache)
        let key = "large-lifespan"
        let value = "Long lived"

        // When
        await coordinator.set(value: value, for: key, lifespan: TimeInterval.greatestFiniteMagnitude)
        let retrieved: String = try await coordinator.value(for: key)

        // Then
        #expect(retrieved == value)
    }
}

// MARK: - CacheMetadata Tests

@Suite("CacheMetadata Tests")
struct CacheMetadataTests {

    @Test("Creates metadata with custom timestamp")
    func createsMetadataWithCustomTimestamp() async throws {
        // Given
        let timestamp: TimeInterval = 1000
        let lifespan: TimeInterval = 3600

        // When
        let metadata = CacheMetadata(timestamp: timestamp, lifespan: lifespan)

        // Then
        #expect(metadata.timestamp == timestamp)
        #expect(metadata.lifespan == lifespan)
    }

    @Test("Detects expired metadata")
    func detectsExpiredMetadata() async throws {
        // Given - Create metadata in the past
        let timestamp = Date.timeIntervalSinceReferenceDate - 7200 // 2 hours ago
        let lifespan: TimeInterval = 3600 // 1 hour lifespan

        // When
        let metadata = CacheMetadata(timestamp: timestamp, lifespan: lifespan)

        // Then
        #expect(metadata.isExpired == true)
    }

    @Test("Detects valid metadata")
    func detectsValidMetadata() async throws {
        // Given - Create fresh metadata
        let timestamp = Date.timeIntervalSinceReferenceDate
        let lifespan: TimeInterval = 3600

        // When
        let metadata = CacheMetadata(timestamp: timestamp, lifespan: lifespan)

        // Then
        #expect(metadata.isExpired == false)
    }

    @Test("Encodes and decodes correctly")
    func encodesAndDecodesCorrectly() async throws {
        // Given
        let original = CacheMetadata(lifespan: 3600)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // When
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(CacheMetadata.self, from: encoded)

        // Then
        #expect(decoded.lifespan == original.lifespan)
        // Timestamp might differ slightly, but should be close
        #expect(abs(decoded.timestamp - original.timestamp) < 1.0)
    }
}
