//
//  DeviceFingerprintConfigurationTests.swift
//  ListenerAuth
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
@testable import ListenerAuth

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
    ///
    /// `authBaseURL` is non-nil so `reconfigure(_:)` actually builds the
    /// `AuthenticationService` this suite reads the threaded fingerprint mode
    /// off. It points at the same discard port
    /// `MusicShareKitConfigureGuardTests` and `MusicShareKitTokenProviderTests`
    /// use: nothing here drives a resolution, and if a racing suite ever
    /// reached this service, a connection to port 9 fails fast rather than
    /// touching a real host.
    func makeConfiguration(
        storage: any DeviceFingerprintStorage = InMemoryDeviceFingerprintStorage()
    ) -> MusicShareKitConfiguration {
        MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            authBaseURL: "http://127.0.0.1:9",
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

    // MARK: - Resolved-mode plumbing (#998, collapsed into AuthenticationService by #1067)
    //
    // Before #1067, `reconfigure(_:)` reported the resolved mode as a
    // dedicated once-per-launch `FingerprintModeResolvedEvent`. That event is
    // gone: the mode now rides as the `fingerprint_mode` property on every
    // `RequestLineAuthResolvedEvent` `AuthenticationService` emits (see that
    // type's `fingerprintMode` doc comment). `AuthenticationService` always
    // gets a real `KeychainTokenStorage` + `DefaultAuthNetworkClient()` from
    // `reconfigure(_:)`, with no test seam for either, so there is no way to
    // drive it through a real resolution here without touching the Keychain
    // or network. What these tests assert instead is the step that lives in
    // `reconfigure(_:)`: the mode it computed is the mode it handed to the
    // service it built, read straight back off that instance. Asserting a
    // separately-published copy of the value would pass even if the argument
    // at the construction site were replaced by a literal. That the service
    // then puts its stored mode on the event is covered in
    // `AuthenticationServiceTests`, where the network client is a double.
    //
    // The branch-to-mode mapping itself (readHit/synchronizableAdd/
    // localFallback/everythingFails) is exhaustively covered independently in
    // `DeviceFingerprintModeTests.swift` against
    // `KeychainDeviceFingerprintStorage.resolve()` directly, so it is not
    // re-covered here.
    //
    // Two tests from before #1067 have no replacement, because the behavior
    // they pinned no longer exists rather than having moved: `resolvedModeIsOncePerLaunch`
    // and `retryDoesNotDoubleEmit` guarded against a *second* capture of the
    // per-launch event on repeated `deviceFingerprint` reads — there is no
    // longer a per-read emission path to double-fire, so the invariant is
    // true by construction. `prematureAccessesRideOnTheLaunchEvent` pinned
    // folding `prematureFingerprintAccesses.count` into that event; the count
    // still rides into the service alongside the mode and still reaches
    // PostHog under the same `premature_access_count` key, but its value is a
    // process-wide total that any suite in a parallel run can advance, so it
    // is pinned where it is deterministic — as an injected value in
    // `AuthenticationServiceTests` and `RequestLineAnalyticsEventsTests` —
    // rather than re-asserted against the live counter here.
    // `PrematureAccessCounterTests` in `DeviceFingerprintModeTests.swift`
    // still covers the counter itself.

    /// The load-bearing property of the original event carries over to its
    /// replacement home: resolution succeeding must still produce a real,
    /// non-placeholder mode, not silently leave the prior configure's value
    /// in place.
    @Test("reconfigure() threads the resolved mode on SUCCESS, not only on failure")
    func successThreadsResolvedMode() async throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubFingerprint = "resolved-ok"
        storage.stubMode = .synchronizable
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        #expect(await MusicShareKit.authService?.fingerprintMode == .synchronizable)
        // Adding a signal must not remove one: the pre-existing failure event
        // stays failure-only.
        #expect(mockAnalytics.typedEvents(ofType: DeviceFingerprintInitFailedEvent.self).isEmpty)
    }

    @Test("reconfigure() threads .failed on a thrown resolution, alongside DeviceFingerprintInitFailedEvent")
    func failureThreadsResolvedMode() async throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubError = AuthenticationError.keychainError(status: errSecMissingEntitlement)
        mockAnalytics.reset()

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))

        #expect(await MusicShareKit.authService?.fingerprintMode == .failed)
        // Both signals fire; the new one does not displace the old one.
        #expect(mockAnalytics.typedEvents(ofType: DeviceFingerprintInitFailedEvent.self).count == 1)
    }

    /// The mode is stamped once, at `reconfigure(_:)` time, and does not
    /// drift when the accessor's inline retry later recovers (or keeps
    /// failing) — mirroring the same "known cost" `AuthenticationService`'s
    /// `fingerprintMode` doc comment describes: a device whose eager init
    /// failed and whose retry then recovered still reports `.failed` on
    /// every `RequestLineAuthResolvedEvent` for the rest of that launch.
    @Test("The resolved mode does not change across later deviceFingerprint reads or the inline retry")
    func resolvedModeIsStableAcrossLaterReads() async throws {
        let storage = InMemoryDeviceFingerprintStorage()
        storage.stubError = AuthenticationError.keychainError(status: errSecInteractionNotAllowed)

        MusicShareKit.reconfigure(makeConfiguration(storage: storage))
        let service = try #require(MusicShareKit.authService)
        #expect(await service.fingerprintMode == .failed)

        // …then Keychain comes online and the retry recovers a value for
        // `deviceFingerprint` itself — but the mode recorded at configure
        // time must not follow it.
        storage.stubError = nil
        storage.stubFingerprint = "recovered-after-unlock"
        for _ in 0..<5 {
            _ = MusicShareKit.deviceFingerprint
        }

        // Read the SAME instance again, not `MusicShareKit.authService` — a
        // racing suite's reconfigure would swap the global out from under
        // this assertion and turn a stability check into a coin flip.
        #expect(await service.fingerprintMode == .failed)
    }

    /// Same wiring, exercised through a real `KeychainDeviceFingerprintStorage`
    /// + `MockKeychainOperations` (rather than `InMemoryDeviceFingerprintStorage`
    /// as the rest of this suite uses) so the branch that actually produces
    /// each mode is real Keychain-shaped code, not a test double standing in
    /// for it. `osStatus` is deliberately not asserted here — post-#1067,
    /// `reconfigure(_:)` no longer reads it at all (the new summary event has
    /// no property for it); see `MusicShareKitConfiguration.swift`'s comment
    /// at the `mode`/`osStatus` do/catch for the full accounting.
    @Test(
        "Each Keychain branch threads its own mode",
        arguments: [
            (KeychainScript.readHit, DeviceFingerprintMode.existing),
            (KeychainScript.synchronizableAdd, DeviceFingerprintMode.synchronizable),
            (KeychainScript.localFallback, DeviceFingerprintMode.local),
            (KeychainScript.everythingFails, DeviceFingerprintMode.failed),
        ]
    )
    func keychainBranchesThreadTheirMode(
        _ script: KeychainScript, _ expectedMode: DeviceFingerprintMode
    ) async throws {
        MusicShareKit.reconfigure(makeConfiguration(storage: script.makeStorage()))
        #expect(await MusicShareKit.authService?.fingerprintMode == expectedMode)
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
