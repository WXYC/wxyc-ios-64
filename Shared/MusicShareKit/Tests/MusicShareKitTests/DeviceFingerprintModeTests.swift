//
//  DeviceFingerprintModeTests.swift
//  MusicShareKit
//
//  Coverage for the resolved-mode plumbing added in #998: which Keychain
//  branch actually produced the device fingerprint, and the OSStatus that
//  explains a non-ideal outcome. Every mode is driven through the
//  `KeychainOperations` seam — nothing here touches the real Keychain.
//
//  Created by Jake Bromberg on 08/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Security
import Testing
@testable import MusicShareKit

/// `errSecMissingEntitlement` is the status the whole of #996 is about: every
/// `KeychainTokenStorage` read and write in 3.2+ fails with it. Pinning it as
/// a parameter here is the point of the fallback-status property — if it is
/// also hitting the fingerprint's synchronizable add, this is the value that
/// will say so.
private let syncFailureStatuses: [OSStatus] = [
    errSecMissingEntitlement,
    errSecParam,
    errSecInteractionNotAllowed,
]

@Suite("Device fingerprint resolved mode")
struct DeviceFingerprintModeTests {

    // MARK: - Read path

    @Test("A value already in the Keychain resolves as .existing, with no add attempted")
    func readHitResolvesExisting() throws {
        let ops = MockKeychainOperations()
        let existing = UUID().uuidString
        ops.queueRead(status: errSecSuccess, data: Data(existing.utf8))

        let resolution = try KeychainDeviceFingerprintStorage(
            accessGroup: nil, operations: ops
        ).resolve()

        #expect(resolution.value == existing)
        // The read query uses kSecAttrSynchronizableAny and does not ask for
        // attributes back, so this path genuinely cannot know whether the
        // stored item syncs. `.existing` says "already present, sync-ness
        // unknown" rather than guessing one of the two write modes.
        #expect(resolution.mode == .existing)
        #expect(resolution.osStatus == errSecSuccess)
        #expect(ops.addCallCount == 0)
    }

    @Test("The reread after a duplicate-item race resolves as .existing")
    func duplicateRaceRereadResolvesExisting() throws {
        let ops = MockKeychainOperations()
        ops.queueRead(status: errSecItemNotFound, data: nil)
        ops.queueAdd(status: errSecDuplicateItem)
        let winner = UUID().uuidString
        ops.queueRead(status: errSecSuccess, data: Data(winner.utf8))

        let resolution = try KeychainDeviceFingerprintStorage(
            accessGroup: nil, operations: ops
        ).resolve()

        // The value we return came off the Keychain, not out of our own add,
        // so the mode has to describe the read that produced it.
        #expect(resolution.value == winner)
        #expect(resolution.mode == .existing)
        #expect(resolution.osStatus == errSecSuccess)
    }

    // MARK: - Write paths

    @Test("A successful synchronizable add resolves as .synchronizable")
    func synchronizableAddResolvesSynchronizable() throws {
        let ops = MockKeychainOperations()
        ops.queueRead(status: errSecItemNotFound, data: nil)
        ops.queueAdd(status: errSecSuccess)

        let resolution = try KeychainDeviceFingerprintStorage(
            accessGroup: nil, operations: ops
        ).resolve()

        #expect(resolution.mode == .synchronizable)
        #expect(resolution.osStatus == errSecSuccess)
        #expect(ops.addCallCount == 1)
        #expect(ops.adds.first?.synchronizable == true)
        #expect(ops.lastAddedValue == resolution.value)
    }

    @Test(
        "A failed synchronizable add followed by a successful local add resolves as .local and carries the synchronizable add's failing status",
        arguments: syncFailureStatuses
    )
    func localFallbackCarriesSyncFailureStatus(_ syncFailure: OSStatus) throws {
        let ops = MockKeychainOperations()
        ops.queueRead(status: errSecItemNotFound, data: nil)
        ops.queueAdd(status: syncFailure)
        ops.queueAdd(status: errSecSuccess)

        let resolution = try KeychainDeviceFingerprintStorage(
            accessGroup: nil, operations: ops
        ).resolve()

        #expect(resolution.mode == .local)
        // Not the local add's errSecSuccess — the value that explains why we
        // are on the fallback at all.
        #expect(resolution.osStatus == syncFailure)

        // The branch order and payload are unchanged by this instrumentation:
        // synchronizable first, local second, same candidate value in both.
        #expect(ops.addCallCount == 2)
        #expect(ops.adds[0].synchronizable == true)
        #expect(ops.adds[1].synchronizable == false)
        #expect(ops.adds[0].value == ops.adds[1].value)
        #expect(ops.adds[1].value == resolution.value)
    }

    @Test("A duplicate on the local add still rereads rather than resolving")
    func localAddDuplicateRereads() throws {
        let ops = MockKeychainOperations()
        ops.queueRead(status: errSecItemNotFound, data: nil)
        ops.queueAdd(status: errSecMissingEntitlement)
        ops.queueAdd(status: errSecDuplicateItem)
        let winner = UUID().uuidString
        ops.queueRead(status: errSecSuccess, data: Data(winner.utf8))

        let resolution = try KeychainDeviceFingerprintStorage(
            accessGroup: nil, operations: ops
        ).resolve()

        #expect(resolution.value == winner)
        #expect(resolution.mode == .existing)
    }

    // MARK: - Failure paths

    @Test("An unrecoverable read failure still throws the read's status")
    func unrecoverableReadThrows() {
        let ops = MockKeychainOperations()
        ops.queueRead(status: errSecMissingEntitlement, data: nil)

        expectKeychainThrow(status: errSecMissingEntitlement) {
            _ = try KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            ).resolve()
        }
    }

    @Test("Both adds failing still throws, so the caller reports .failed")
    func bothAddsFailingThrows() {
        let ops = MockKeychainOperations()
        ops.queueRead(status: errSecItemNotFound, data: nil)
        ops.queueAdd(status: errSecMissingEntitlement)
        ops.queueAdd(status: errSecMissingEntitlement)

        expectKeychainThrow(status: errSecMissingEntitlement) {
            _ = try KeychainDeviceFingerprintStorage(
                accessGroup: nil, operations: ops
            ).resolve()
        }
    }

    // MARK: - InMemory double

    /// Deliberately not `DeviceFingerprintMode.allCases`: a resolution never
    /// carries `.failed` (see `DeviceFingerprintResolution.osStatus`), which is
    /// derived by the caller from a thrown error. Driving the double over every
    /// case would make this test the one place that constructs the state the
    /// type documents as impossible.
    @Test(
        "InMemoryDeviceFingerprintStorage reports its stubbed mode",
        arguments: [DeviceFingerprintMode.existing, .synchronizable, .local]
    )
    func inMemoryReportsStubbedMode(_ mode: DeviceFingerprintMode) throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubMode = mode

        let resolution = try storage.resolve()

        #expect(resolution.mode == mode)
        // ensure() now reaches the double through the protocol extension, so
        // suites that count ensure() calls keep working either way.
        #expect(storage.ensureCallCount == 1)
        #expect(try storage.ensure() == resolution.value)
        #expect(storage.ensureCallCount == 2)
    }
}

// MARK: - Assertion Helpers

/// `AuthenticationError` is not `Equatable`, so `#expect(throws:)` cannot pin a
/// specific case. Unwrap the payload by hand instead of settling for
/// `AuthenticationError.self`, which would pass on any status at all.
private func expectKeychainThrow(
    status expected: OSStatus,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> Void
) {
    do {
        try body()
        Issue.record("Expected AuthenticationError.keychainError(status: \(expected))", sourceLocation: sourceLocation)
    } catch AuthenticationError.keychainError(let status) {
        #expect(status == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
    }
}

// MARK: - Premature access counter

@Suite("PrematureAccessCounter")
struct PrematureAccessCounterTests {

    @Test("record() increments, and the count does not reset when read")
    func recordIncrementsAndPersists() {
        let counter = PrematureAccessCounter()
        counter.record()
        counter.record()
        counter.record()

        // Read twice: the count is deliberately monotonic rather than
        // drain-on-read, so a second reader sees the same total.
        #expect(counter.count == 3)
        #expect(counter.count == 3)
    }
}
