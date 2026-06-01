//
//  DeviceFingerprintTests.swift
//  MusicShareKit
//
//  Tests for DeviceFingerprintStorage covering the atomic add-or-reread
//  race-handling logic (iOS#351 / D3) and real-Keychain persistence.
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Security
import Testing
@testable import MusicShareKit

@Suite("DeviceFingerprintStorage Tests")
struct DeviceFingerprintTests {

    // MARK: - InMemoryDeviceFingerprintStorage

    @Suite("InMemoryDeviceFingerprintStorage")
    struct InMemoryTests {
        @Test("First call generates and persists a UUIDv4")
        func firstCallGenerates() throws {
            let storage = InMemoryDeviceFingerprintStorage()
            let value = try storage.ensure()

            #expect(!value.isEmpty)
            #expect(UUID(uuidString: value) != nil)
            #expect(storage.ensureCallCount == 1)
        }

        @Test("Second call returns the same value")
        func secondCallReturnsSame() throws {
            let storage = InMemoryDeviceFingerprintStorage()
            let first = try storage.ensure()
            let second = try storage.ensure()

            #expect(first == second)
            #expect(storage.ensureCallCount == 2)
        }

        @Test("Stub fingerprint overrides generation")
        func stubOverrides() throws {
            let storage = InMemoryDeviceFingerprintStorage()
            storage.stubFingerprint = "stub-value"

            #expect(try storage.ensure() == "stub-value")
            #expect(try storage.ensure() == "stub-value")
        }

        @Test("Stub error throws on ensure")
        func stubErrorThrows() {
            let storage = InMemoryDeviceFingerprintStorage()
            storage.stubError = AuthenticationError.keychainError(
                status: errSecInteractionNotAllowed
            )

            #expect(throws: AuthenticationError.self) {
                _ = try storage.ensure()
            }
        }
    }

    // MARK: - KeychainDeviceFingerprintStorage (mocked seam)

    @Suite("KeychainDeviceFingerprintStorage mocked seam")
    struct MockedSeamTests {

        @Test("First call generates and writes when Keychain is empty")
        func firstCallGenerates() throws {
            let ops = MockKeychainOperations()
            ops.queueRead(status: errSecItemNotFound, data: nil)
            ops.queueAdd(status: errSecSuccess)

            let storage = KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            )

            let value = try storage.ensure()
            #expect(!value.isEmpty)
            #expect(UUID(uuidString: value) != nil)
            #expect(ops.readCallCount == 1)
            #expect(ops.addCallCount == 1)

            // The add payload should carry the same UUID we returned.
            let added = ops.lastAddedValue
            #expect(added == value)
        }

        @Test("Existing Keychain value is returned without add")
        func existingValueReturned() throws {
            let ops = MockKeychainOperations()
            let existing = UUID().uuidString
            ops.queueRead(status: errSecSuccess, data: Data(existing.utf8))

            let storage = KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            )

            let value = try storage.ensure()
            #expect(value == existing)
            #expect(ops.readCallCount == 1)
            #expect(ops.addCallCount == 0)
        }

        @Test("errSecDuplicateItem on add triggers reread of the winning value")
        func duplicateRaceRereads() throws {
            let ops = MockKeychainOperations()
            // First read: empty (both processes race here).
            ops.queueRead(status: errSecItemNotFound, data: nil)
            // First add: another process beat us.
            ops.queueAdd(status: errSecDuplicateItem)
            // Loop iteration 2 reread: returns the winner's value.
            let winner = UUID().uuidString
            ops.queueRead(status: errSecSuccess, data: Data(winner.utf8))

            let storage = KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            )

            let value = try storage.ensure()
            #expect(value == winner)
            #expect(ops.readCallCount == 2)
            #expect(ops.addCallCount == 1)
            // The local UUID we tried to add must NOT be what we return —
            // the winning process's value wins.
            #expect(value != ops.lastAddedValue)
        }

        @Test("Sync add failure falls back to non-synchronizable add")
        func syncFallback() throws {
            let ops = MockKeychainOperations()
            ops.queueRead(status: errSecItemNotFound, data: nil)
            // First add (synchronizable) fails.
            ops.queueAdd(status: errSecParam)
            // Second add (non-synchronizable) succeeds.
            ops.queueAdd(status: errSecSuccess)

            let storage = KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            )

            let value = try storage.ensure()
            #expect(!value.isEmpty)
            #expect(ops.addCallCount == 2)

            // First add carried synchronizable=true, second carried false.
            #expect(ops.adds[0].synchronizable == true)
            #expect(ops.adds[1].synchronizable == false)
            // Both should carry the same candidate value.
            #expect(ops.adds[0].value == ops.adds[1].value)
        }

        @Test("Read failure other than ItemNotFound throws")
        func unrecoverableReadThrows() {
            let ops = MockKeychainOperations()
            ops.queueRead(status: errSecInteractionNotAllowed, data: nil)

            let storage = KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            )

            #expect(throws: AuthenticationError.self) {
                _ = try storage.ensure()
            }
        }

        @Test("Empty data on successful read throws decode error")
        func emptyDataDecodeError() {
            let ops = MockKeychainOperations()
            ops.queueRead(status: errSecSuccess, data: Data())

            let storage = KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            )

            do {
                _ = try storage.ensure()
                Issue.record("Expected throw")
            } catch AuthenticationError.keychainError(let status) {
                #expect(status == errSecDecode)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }

        @Test("Retry cap fires when both add attempts keep returning duplicate")
        func retryCap() {
            // Pathological case: read keeps returning ItemNotFound, add keeps
            // returning errSecDuplicateItem. The loop must terminate after 3
            // iterations rather than livelock.
            let ops = MockKeychainOperations()
            for _ in 0..<10 {
                ops.queueRead(status: errSecItemNotFound, data: nil)
                ops.queueAdd(status: errSecDuplicateItem)
            }

            let storage = KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            )

            #expect(throws: AuthenticationError.self) {
                _ = try storage.ensure()
            }
            #expect(ops.readCallCount == 3)
            #expect(ops.addCallCount == 3)
        }

        @Test("Access group is forwarded into read and add queries")
        func accessGroupForwarded() throws {
            let ops = MockKeychainOperations()
            ops.queueRead(status: errSecItemNotFound, data: nil)
            ops.queueAdd(status: errSecSuccess)

            let storage = KeychainDeviceFingerprintStorage(
                accessGroup: "92V374HC38.group.wxyc.iphone", operations: ops
            )

            _ = try storage.ensure()

            #expect(ops.lastReadAccessGroup == "92V374HC38.group.wxyc.iphone")
            #expect(ops.adds.first?.accessGroup == "92V374HC38.group.wxyc.iphone")
        }
    }

    // MARK: - Real Keychain Integration

    @Suite("KeychainDeviceFingerprintStorage real Keychain", .serialized)
    struct RealKeychainTests {

        /// Use a test-isolated service so running these tests on a developer's
        /// machine (or any device with WXYC installed) doesn't wipe the host
        /// app's real production fingerprint — which would force a fresh
        /// UUID generation on next app launch and break server-side
        /// ban-evasion tracking for that user.
        static let testService = "fm.wxyc.devicefingerprint.test"
        static let testAccount = "fingerprint.test"

        static func makeStorage() -> KeychainDeviceFingerprintStorage {
            KeychainDeviceFingerprintStorage(
                accessGroup: nil,
                operations: DefaultKeychainOperations(),
                service: testService,
                account: testAccount
            )
        }

        init() {
            // Clean up any leftover test items so each suite run starts fresh.
            deleteRealKeychainFingerprint(
                service: Self.testService, account: Self.testAccount
            )
        }

        @Test("Two instances see the same UUID")
        func twoInstancesShareValue() throws {
            let a = Self.makeStorage()
            let b = Self.makeStorage()

            let valueA = try a.ensure()
            let valueB = try b.ensure()

            #expect(valueA == valueB)
            #expect(UUID(uuidString: valueA) != nil)

            deleteRealKeychainFingerprint(
                service: Self.testService, account: Self.testAccount
            )
        }

        @Test("Repeated calls on the same instance are idempotent")
        func repeatedCallsIdempotent() throws {
            let storage = Self.makeStorage()
            let first = try storage.ensure()
            let second = try storage.ensure()
            let third = try storage.ensure()

            #expect(first == second)
            #expect(second == third)

            deleteRealKeychainFingerprint(
                service: Self.testService, account: Self.testAccount
            )
        }
    }
}

// MARK: - Mock Keychain Operations

/// Records every read and add against the seam, and serves canned responses
/// in FIFO order so tests can script a sequence of cross-process race outcomes.
final class MockKeychainOperations: KeychainOperations, @unchecked Sendable {

    struct AddRecord {
        let value: String
        let synchronizable: Bool
        let accessGroup: String?
    }

    private let lock = NSLock()

    private var queuedReads: [(status: OSStatus, data: Data?)] = []
    private var queuedAdds: [OSStatus] = []

    private(set) var readCallCount = 0
    private(set) var addCallCount = 0
    private(set) var lastReadAccessGroup: String?
    private(set) var adds: [AddRecord] = []

    var lastAddedValue: String? { adds.last?.value }

    func queueRead(status: OSStatus, data: Data?) {
        lock.withLock { queuedReads.append((status, data)) }
    }

    func queueAdd(status: OSStatus) {
        lock.withLock { queuedAdds.append(status) }
    }

    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        lock.lock()
        defer { lock.unlock() }
        readCallCount += 1
        let dict = query as NSDictionary
        lastReadAccessGroup = dict[kSecAttrAccessGroup as String] as? String

        guard !queuedReads.isEmpty else {
            return (errSecItemNotFound, nil)
        }
        return queuedReads.removeFirst()
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        addCallCount += 1
        let dict = attributes as NSDictionary
        let data = dict[kSecValueData as String] as? Data
        let value = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let sync = (dict[kSecAttrSynchronizable as String] as? Bool) == true
        let group = dict[kSecAttrAccessGroup as String] as? String
        adds.append(AddRecord(value: value, synchronizable: sync, accessGroup: group))

        guard !queuedAdds.isEmpty else {
            return errSecSuccess
        }
        return queuedAdds.removeFirst()
    }
}

// MARK: - Real-Keychain Cleanup

private func deleteRealKeychainFingerprint(service: String, account: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
    ]
    _ = SecItemDelete(query as CFDictionary)
}
