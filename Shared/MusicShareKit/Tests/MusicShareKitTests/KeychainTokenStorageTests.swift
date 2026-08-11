//
//  KeychainTokenStorageTests.swift
//  MusicShareKit
//
//  Integration tests for KeychainTokenStorage using the real Keychain.
//  Verifies round-trip persistence, synchronizable fallback, and load fallback.
//
//  Created by Jake Bromberg on 04/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AnalyticsTesting
import Foundation
import Security
import Testing
@testable import MusicShareKit

private let testService = "org.wxyc.app.auth.test"
private let testAccount = "anonymous-session-test"

@Suite("KeychainTokenStorage Tests", .serialized)
struct KeychainTokenStorageTests {

    let mockAnalytics = MockStructuredAnalytics()

    init() {
        // Clean up any leftover items from prior test runs
        deleteAllTestKeychainItems()
    }

    // MARK: - Real Keychain, iOS Simulator only
    //
    // The four tests below touch the real Keychain and are gated on
    // `WXYC_SKIP_KNOWN_FLAKES`. Two corrections to the reason string this
    // section used to carry:
    //
    // 1. The "(#371)" citation was wrong. #371 tracks three CI-load flakes in
    //    `Shared/Playback`/`Shared/AppServices` (Widget relevance,
    //    stream-error analytics, render-tap teardown) and never mentions
    //    Keychain or entitlements. `51e0c07a` borrowed that issue's mechanism
    //    and its number together; only the mechanism applied.
    //
    // 2. This is not a flake, it is deterministic. Run inside the iOS
    //    Simulator, the sandboxed SPM test-bundle process has no
    //    Keychain-access entitlement, so every `SecItemAdd` /
    //    `SecItemCopyMatching` below fails with `errSecMissingEntitlement`
    //    (-34018), every time. On a plain macOS host under `swift test` they
    //    all pass: an ordinary macOS process can use the login Keychain
    //    without that entitlement, and these tests pass `accessGroup: nil`, so
    //    no entitlement-bearing access group ever enters the query. No
    //    physical device is involved on either side — contrary to the original
    //    skip commit's "local runs still exercise the path on developers'
    //    devices".
    //
    // Which CI path these traits affect is easy to get backwards, so, exactly:
    //
    //   * The host `swift test` step DOES run all four, unskipped.
    //     `MusicShareKit` is on `affected-tests.sh`'s `SPM_RUNNABLE` list, so
    //     the "swift test SPM-runnable packages" step runs `swift test
    //     --package-path Shared/MusicShareKit`, and that step deliberately
    //     never sets `WXYC_SKIP_KNOWN_FLAKES` — see the env-scoping comment on
    //     the `TEST_RUNNER_WXYC_SKIP_KNOWN_FLAKES` step env in
    //     `.github/workflows/build-and-test.yml`.
    //   * The xcodebuild/Simulator step never runs them at all, skipped or
    //     otherwise. `MusicShareKitTests` is excluded on both branches of
    //     `affected-tests.sh`: explicitly on the run-all path
    //     (`-skip-testing:MusicShareKitTests`), and implicitly on the affected
    //     path, where `SPM_RUNNABLE` packages `continue` before their
    //     `TEST_TARGETS` entries are collected.
    //
    // So the one step that sets the var is the one step that never runs this
    // target, and these traits cannot fire in CI at all. Their real audience is
    // a LOCAL full-plan run, which `docs/build-test.md` documents as requiring
    // `TEST_RUNNER_WXYC_SKIP_KNOWN_FLAKES=1`. (`build-and-test.yml` is
    // `workflow_dispatch`-only regardless, so none of the above happens until
    // someone dispatches it by hand.)
    //
    // Retiring these traits therefore means making that local Simulator run
    // stop hitting `errSecMissingEntitlement` — i.e. giving the Simulator's SPM
    // test-bundle process a Keychain-access entitlement. Dropping the coverage
    // from the xcodebuild path is not the lever it looks like: CI already does
    // exactly that. Either way it is a test-plan/signing decision, not a
    // comment fix — left as-is here.

    // MARK: - Round-Trip Persistence

    @Test(
        "Save and load round-trips session across instances",
        .disabled(
            if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1",
            "Deterministic errSecMissingEntitlement in the iOS Simulator's SPM test bundle — not a flake, not #371. Passes under swift test on the macOS host, the path CI uses. See the \"Real Keychain, iOS Simulator only\" comment above."
        )
    )
    func saveAndLoadRoundTripsAcrossInstances() throws {
        let session = AuthSession(
            sessionToken: "persist-session", jwt: "persist-jwt",
            userId: "persist-user-123",
            createdAt: Date(),
            expiresAt: nil
        )

        let storage1 = makeStorage(synchronizable: false)
        try storage1.save(session)

        // Load with a fresh instance (simulates app relaunch)
        let storage2 = makeStorage(synchronizable: false)
        let loaded = try storage2.load()

        #expect(loaded?.jwt == session.jwt)
        #expect(loaded?.userId == session.userId)

        try storage2.delete()
    }

    // MARK: - Synchronizable Save Fallback

    @Test(
        "Save falls back to non-synchronizable when iCloud Keychain is unavailable",
        .disabled(
            if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1",
            "Deterministic errSecMissingEntitlement in the iOS Simulator's SPM test bundle — not a flake, not #371. Passes under swift test on the macOS host, the path CI uses. See the \"Real Keychain, iOS Simulator only\" comment above."
        )
    )
    func saveFallsBackToNonSynchronizable() throws {
        let session = AuthSession(
            sessionToken: "fallback-session", jwt: "fallback-jwt",
            userId: "fallback-user-456",
            createdAt: Date(),
            expiresAt: nil
        )

        // Save with synchronizable=true. On macOS (swift test), iCloud Keychain
        // is unavailable, so the sync save fails and falls back to non-sync.
        let storage = makeStorage(synchronizable: true)
        try storage.save(session)

        // Load should find the item regardless of how it was saved
        let loaded = try storage.load()
        #expect(loaded?.jwt == session.jwt)
        #expect(loaded?.userId == session.userId)

        try storage.delete()
    }

    @Test(
        "Save fallback persists across instances",
        .disabled(
            if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1",
            "Deterministic errSecMissingEntitlement in the iOS Simulator's SPM test bundle — not a flake, not #371. Passes under swift test on the macOS host, the path CI uses. See the \"Real Keychain, iOS Simulator only\" comment above."
        )
    )
    func saveFallbackPersistsAcrossInstances() throws {
        let session = AuthSession(
            sessionToken: "relaunch-session", jwt: "relaunch-jwt",
            userId: "relaunch-user",
            createdAt: Date(),
            expiresAt: nil
        )

        // Save with synchronizable=true (may fall back to non-sync)
        let storage1 = makeStorage(synchronizable: true)
        try storage1.save(session)

        // Load with a fresh synchronizable=true instance (simulates app relaunch)
        let storage2 = makeStorage(synchronizable: true)
        let loaded = try storage2.load()

        #expect(loaded?.jwt == session.jwt)
        #expect(loaded?.userId == session.userId)

        try storage2.delete()
    }

    // MARK: - Load Fallback

    @Test(
        "Load with synchronizable=true finds non-synchronizable items",
        .disabled(
            if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1",
            "Deterministic errSecMissingEntitlement in the iOS Simulator's SPM test bundle — not a flake, not #371. Passes under swift test on the macOS host, the path CI uses. See the \"Real Keychain, iOS Simulator only\" comment above."
        )
    )
    func loadFindsFallbackItems() throws {
        let session = AuthSession(
            sessionToken: "nonsync-session", jwt: "nonsync-jwt",
            userId: "nonsync-user",
            createdAt: Date(),
            expiresAt: nil
        )

        // Save directly as non-synchronizable (simulates a fallback save)
        let data = try JSONEncoder().encode(session)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        #expect(addStatus == errSecSuccess)

        // Load with synchronizable=true should still find the non-sync item
        let storage = makeStorage(synchronizable: true)
        let loaded = try storage.load()

        #expect(loaded?.jwt == session.jwt)
        #expect(loaded?.userId == session.userId)

        try storage.delete()
    }

    // MARK: - Access Group Plumbing

    /// Verifies the `accessGroup` constructor argument is propagated into the
    /// underlying Keychain query dictionary. Without this, both call sites'
    /// keychain items live in per-process containers and the Share Extension
    /// cannot read a session cached by the main app (issue #336).
    ///
    /// We cannot exercise a full cross-process round-trip in a Swift Package
    /// unit-test bundle — Keychain access groups require a signed host with
    /// matching entitlements — so this test introspects the query that
    /// `KeychainTokenStorage` builds and asserts the `kSecAttrAccessGroup`
    /// key is present iff `accessGroup` was set.
    @Test("baseQuery omits kSecAttrAccessGroup when accessGroup is nil")
    func baseQueryOmitsAccessGroupWhenNil() {
        let storage = KeychainTokenStorage(
            service: testService,
            account: testAccount,
            accessGroup: nil,
            synchronizable: false,
            analytics: mockAnalytics
        )

        let query = storage.baseQuery()

        #expect(query[kSecAttrAccessGroup as String] == nil)
    }

    @Test("baseQuery includes kSecAttrAccessGroup when accessGroup is set")
    func baseQueryIncludesAccessGroupWhenSet() {
        // Must match AppConfiguration.keychainAccessGroup; the pin lives in
        // AppConfigurationTests.keychainAccessGroupMatchesEntitlement. We
        // don't import AppServices here to avoid a cross-package test dep.
        let group = "92V374HC38.group.wxyc.iphone"
        let storage = KeychainTokenStorage(
            service: testService,
            account: testAccount,
            accessGroup: group,
            synchronizable: false,
            analytics: mockAnalytics
        )

        let query = storage.baseQuery()

        #expect(query[kSecAttrAccessGroup as String] as? String == group)
    }

    /// Pins the production combination: when the configured Keychain item is
    /// BOTH iCloud-synchronizable AND scoped to a custom access group, BOTH
    /// attributes must coexist in the query. A future refactor that branched
    /// (`if synchronizable { ... } else if let group { ... }`) would silently
    /// regress one of them and only this test would catch it.
    @Test("baseQuery sets both kSecAttrSynchronizable and kSecAttrAccessGroup when both are configured")
    func baseQueryIncludesBothSyncAndAccessGroup() {
        let group = "92V374HC38.group.wxyc.iphone"
        let storage = KeychainTokenStorage(
            service: testService,
            account: testAccount,
            accessGroup: group,
            synchronizable: true,
            analytics: mockAnalytics
        )

        let query = storage.baseQuery()

        #expect(query[kSecAttrAccessGroup as String] as? String == group)
        // The implementation sets kSecAttrSynchronizable to kSecAttrSynchronizableAny
        // when synchronizable=true (so the query matches both synced and
        // non-synced items). Compare as String — the CF constant bridges to
        // a Swift String at the dictionary boundary.
        let syncAttr = query[kSecAttrSynchronizable as String] as? String
        #expect(syncAttr == kSecAttrSynchronizableAny as String)
    }

    // MARK: - Helpers

    private func makeStorage(synchronizable: Bool) -> KeychainTokenStorage {
        KeychainTokenStorage(
            service: testService,
            account: testAccount,
            accessGroup: nil,
            synchronizable: synchronizable,
            analytics: mockAnalytics
        )
    }

    private func deleteAllTestKeychainItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)

        // Also delete non-synchronizable items (queries without kSecAttrSynchronizable
        // won't match synchronizable items and vice versa)
        let nonSyncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: testAccount
        ]
        SecItemDelete(nonSyncQuery as CFDictionary)
    }
}
