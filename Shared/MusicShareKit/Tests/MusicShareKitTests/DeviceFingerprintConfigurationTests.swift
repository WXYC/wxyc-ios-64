//
//  DeviceFingerprintConfigurationTests.swift
//  MusicShareKit
//
//  Tests for the MusicShareKitConfiguration / MusicShareKit.reconfigure(...)
//  device-fingerprint plumbing (iOS#351 Step 2). Uses reconfigure(_:), not
//  the guarded configure(_:), because this suite depends on every call
//  rebuilding state with fresh doubles (#956).
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AnalyticsTesting
import Foundation
import Security
import Testing
@testable import MusicShareKit

@Suite("MusicShareKit fingerprint configure plumbing", .serialized)
struct DeviceFingerprintConfigurationTests {

    let mockAnalytics = MockStructuredAnalytics()

    /// Build a configuration with an explicit fingerprint storage, so tests
    /// don't touch the real Keychain (which would fail in this SPM test bundle
    /// due to the well-known errSecMissingEntitlement constraint).
    ///
    /// `requestOMaticURL` matches `RequestServiceTests`' value because suites
    /// can interleave on `MusicShareKit`'s global static state — if both call
    /// `configure(...)` with different URLs concurrently, whichever happens
    /// to land last wins and breaks the other suite's assertions.
    func makeConfiguration(
        storage: any DeviceFingerprintStorage = InMemoryDeviceFingerprintStorage()
    ) -> MusicShareKitConfiguration {
        MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            authBaseURL: nil,
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: storage
        )
    }

    @Test("configure() eagerly materializes the fingerprint")
    func eagerInit() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubFingerprint = "fingerprint-eager-42"

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        // Capture immediately — within MusicShareKitTests' parallelizable
        // run, a concurrent suite may reconfigure MusicShareKit globals
        // between the configure call and any later access; reading count
        // synchronously catches the eager-init result before that can happen.
        #expect(storage.ensureCallCount == 1)
        // `MusicShareKit.deviceFingerprint` may have been swapped by a
        // racing suite's configure(). The load-bearing behavior is "eager
        // call was made," which `ensureCallCount == 1` already verifies.
    }

    @Test("deviceFingerprint accessor is cached after eager init")
    func cachedAfterEager() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubFingerprint = "cached-val"

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))
        let postConfigureCount = storage.ensureCallCount

        _ = MusicShareKit.deviceFingerprint
        _ = MusicShareKit.deviceFingerprint
        _ = MusicShareKit.deviceFingerprint

        // The accessor reads must not grow unboundedly — N reads of a cached
        // fingerprint must not result in N additional ensure() calls.
        // Asserting "== 1" exactly is over-specific under MusicShareKitTests'
        // parallel execution: a concurrent suite that reconfigures
        // MusicShareKit can race ours and trigger ONE retry. We bound by 2
        // (eager call + at-most-one retry) to tolerate that without losing
        // the load-bearing "is cached" property — a regression to "no caching"
        // would push the count to 4 (eager + 3 reads).
        #expect(storage.ensureCallCount <= postConfigureCount + 1)
    }

    @Test("configure() captures DeviceFingerprintInitFailedEvent on throw")
    func failureCapturesAnalytics() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubError = AuthenticationError.keychainError(
            status: errSecInteractionNotAllowed
        )
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        let failures = mockAnalytics.typedEvents(ofType: DeviceFingerprintInitFailedEvent.self)
        #expect(failures.count == 1)
    }

    @Test("Accessor's inline retry recovers when Keychain comes online between configure() and first access")
    func retryAfterFailedEager() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        // Eager init fails (e.g., pre-first-unlock).
        storage.stubError = AuthenticationError.keychainError(
            status: errSecInteractionNotAllowed
        )

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        // …then later (e.g., after first-unlock) Keychain comes online.
        // The accessor's at-most-once retry fires on the next read.
        storage.stubError = nil
        storage.stubFingerprint = "recovered-after-unlock"

        #expect(MusicShareKit.deviceFingerprint == "recovered-after-unlock")
    }

    @Test("Retry burns at-most-once: continuing-failure path returns nil without hammering Keychain")
    func accessorNilWhenStorageBroken() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubError = AuthenticationError.keychainError(
            status: errSecInteractionNotAllowed
        )

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))
        let preCount = storage.ensureCallCount  // 1 from eager configure

        // Multiple accesses while storage continues failing.
        for _ in 0..<5 {
            #expect(MusicShareKit.deviceFingerprint == nil)
        }

        // Exactly one retry attempt should have been made, regardless of
        // how many times the accessor was called.
        #expect(storage.ensureCallCount == preCount + 1)
    }

    // MARK: - Resolved-mode telemetry (#998)

    /// The load-bearing property of the whole event: it fires when nothing went
    /// wrong. A failure-only metric reads identically to a metric that stopped
    /// reporting, and that ambiguity is what hid #996 for two weeks.
    @Test("configure() captures FingerprintModeResolvedEvent on SUCCESS, not only on failure")
    func successCapturesResolvedMode() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubFingerprint = "resolved-ok"
        storage.stubMode = .synchronizable
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        let resolved = mockAnalytics.typedEvents(ofType: FingerprintModeResolvedEvent.self)
        #expect(resolved.count == 1)
        #expect(resolved.first?.mode == "synchronizable")
        #expect(resolved.first?.osStatus == errSecSuccess)
        // Adding a signal must not remove one: the pre-existing failure event
        // stays failure-only.
        #expect(mockAnalytics.typedEvents(ofType: DeviceFingerprintInitFailedEvent.self).isEmpty)
    }

    @Test("configure() captures FingerprintModeResolvedEvent(.failed) carrying the thrown OSStatus")
    func failureCapturesResolvedMode() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubError = AuthenticationError.keychainError(status: errSecMissingEntitlement)
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        let resolved = mockAnalytics.typedEvents(ofType: FingerprintModeResolvedEvent.self)
        #expect(resolved.count == 1)
        #expect(resolved.first?.mode == "failed")
        #expect(resolved.first?.osStatus == -34018)
        // Both events fire; the new one does not displace the old one.
        #expect(mockAnalytics.typedEvents(ofType: DeviceFingerprintInitFailedEvent.self).count == 1)
    }

    @Test(
        "Each Keychain branch reaches analytics as its own mode",
        arguments: [
            (KeychainScript.readHit, "existing", errSecSuccess),
            (KeychainScript.synchronizableAdd, "synchronizable", errSecSuccess),
            (KeychainScript.localFallback, "local", errSecMissingEntitlement),
            (KeychainScript.everythingFails, "failed", errSecMissingEntitlement),
        ]
    )
    func keychainBranchesReachAnalytics(
        _ script: KeychainScript, _ expectedMode: String, _ expectedStatus: OSStatus
    ) throws {
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: script.makeStorage()))

        let resolved = mockAnalytics.typedEvents(ofType: FingerprintModeResolvedEvent.self)
        #expect(resolved.count == 1)
        #expect(resolved.first?.mode == expectedMode)
        #expect(resolved.first?.osStatus == expectedStatus)
    }

    /// One summary event per launch is the budget — the PostHog org is on the
    /// free tier at its six-project limit and came off a quota exhaustion on
    /// 2026-08-04. Per-operation capture is not affordable.
    @Test("The resolved-mode event is emitted once per configure, not once per fingerprint read")
    func resolvedModeIsOncePerLaunch() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubFingerprint = "once-per-launch"
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))
        for _ in 0..<10 {
            _ = MusicShareKit.deviceFingerprint
        }

        #expect(mockAnalytics.typedEvents(ofType: FingerprintModeResolvedEvent.self).count == 1)
    }

    /// The accessor's at-most-once inline retry carries a "don't double-emit"
    /// comment for the failure event. The per-launch mode event is bound by the
    /// same rule.
    @Test("The accessor's inline retry does not emit a second resolved-mode event")
    func retryDoesNotDoubleEmit() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubError = AuthenticationError.keychainError(status: errSecInteractionNotAllowed)
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        storage.stubError = nil
        storage.stubFingerprint = "recovered-after-unlock"
        _ = MusicShareKit.deviceFingerprint
        _ = MusicShareKit.deviceFingerprint

        #expect(mockAnalytics.typedEvents(ofType: FingerprintModeResolvedEvent.self).count == 1)
        #expect(mockAnalytics.typedEvents(ofType: DeviceFingerprintInitFailedEvent.self).count == 1)
    }

    /// (B) The pre-configure silent nil. `MusicShareKit.deviceFingerprint`'s
    /// `guard let config = _configuration` returns nil with no analytics
    /// service in existence to report to — `_configuration` is where the
    /// analytics service lives. The access is counted and the total rides on
    /// the next launch event instead.
    ///
    /// The count is asserted as a lower bound, not an equality: it is a
    /// process-wide monotonic counter and `MusicShareKitTests` runs its suites
    /// in parallel, so another suite could contribute. A regression to "not
    /// wired" reads as 0 and still fails here.
    @Test("Pre-configure fingerprint reads are counted and reported on the launch event")
    func prematureAccessesRideOnTheLaunchEvent() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubFingerprint = "premature-probe"

        MusicShareKit.prematureFingerprintAccesses.record()
        MusicShareKit.prematureFingerprintAccesses.record()
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        let resolved = mockAnalytics.typedEvents(ofType: FingerprintModeResolvedEvent.self)
        #expect(resolved.count == 1)
        #expect((resolved.first?.prematureAccessCount ?? -1) >= 2)
    }

    @Test("Configuration default storage is a KeychainDeviceFingerprintStorage")
    func defaultStorageType() {
        let config = MusicShareKitConfiguration(
            requestOMaticURL: "https://example.invalid/request",
            authBaseURL: nil,
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics
        )

        // The default value must be a KeychainDeviceFingerprintStorage so
        // production callers (WXYCApp + ShareViewController) don't have to
        // know about the new field. (Step 8 in the plan.)
        #expect(config.deviceFingerprintStorage is KeychainDeviceFingerprintStorage)
    }
}

// MARK: - Keychain Scripts

/// Canned `KeychainOperations` sequences, one per branch of
/// `KeychainDeviceFingerprintStorage.resolve()`. Named cases rather than inline
/// queues so the parameterized test above reads as "this branch produces that
/// mode", and so no test here can reach the real Keychain.
enum KeychainScript: Sendable {
    /// A value is already persisted; no add is attempted.
    case readHit
    /// Nothing persisted; the synchronizable add succeeds.
    case synchronizableAdd
    /// Nothing persisted; the synchronizable add fails with the status #996 is
    /// about, and the local-only add succeeds.
    case localFallback
    /// The read itself fails unrecoverably, so `resolve()` throws.
    case everythingFails

    func makeStorage() -> KeychainDeviceFingerprintStorage {
        let ops = MockKeychainOperations()
        switch self {
        case .readHit:
            ops.queueRead(status: errSecSuccess, data: Data(UUID().uuidString.utf8))
        case .synchronizableAdd:
            ops.queueRead(status: errSecItemNotFound, data: nil)
            ops.queueAdd(status: errSecSuccess)
        case .localFallback:
            ops.queueRead(status: errSecItemNotFound, data: nil)
            ops.queueAdd(status: errSecMissingEntitlement)
            ops.queueAdd(status: errSecSuccess)
        case .everythingFails:
            ops.queueRead(status: errSecMissingEntitlement, data: nil)
        }
        return KeychainDeviceFingerprintStorage(accessGroup: nil, operations: ops)
    }
}
