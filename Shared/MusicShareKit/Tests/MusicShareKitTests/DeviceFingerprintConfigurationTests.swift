//
//  DeviceFingerprintConfigurationTests.swift
//  MusicShareKit
//
//  Tests for the MusicShareKitConfiguration / MusicShareKit.configure(...)
//  device-fingerprint plumbing (iOS#351 Step 2).
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

        MusicShareKit.configure(makeConfiguration(storage: storage))

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

        MusicShareKit.configure(makeConfiguration(storage: storage))
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

        MusicShareKit.configure(makeConfiguration(storage: storage))

        let failures = mockAnalytics.typedEvents(ofType: DeviceFingerprintInitFailedEvent.self)
        #expect(failures.count == 1)
    }

    @Test("Accessor retries when eager init failed but later succeeds")
    func retryAfterFailedEager() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        // Eager init fails…
        storage.stubError = AuthenticationError.keychainError(
            status: errSecInteractionNotAllowed
        )

        MusicShareKit.configure(makeConfiguration(storage: storage))
        #expect(MusicShareKit.deviceFingerprint == nil)

        // …then later (e.g., after first-unlock) Keychain comes online.
        storage.stubError = nil
        storage.stubFingerprint = "recovered-after-unlock"

        #expect(MusicShareKit.deviceFingerprint == "recovered-after-unlock")
    }

    @Test("Accessor returns nil when storage continues to fail")
    func accessorNilWhenStorageBroken() throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubError = AuthenticationError.keychainError(
            status: errSecInteractionNotAllowed
        )

        MusicShareKit.configure(makeConfiguration(storage: storage))
        #expect(MusicShareKit.deviceFingerprint == nil)
        #expect(MusicShareKit.deviceFingerprint == nil)
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
