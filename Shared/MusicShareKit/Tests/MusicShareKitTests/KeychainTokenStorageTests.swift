//
//  KeychainTokenStorageTests.swift
//  MusicShareKit
//
//  Integration tests for KeychainTokenStorage using the real Keychain.
//  Verifies round-trip persistence, synchronizable fallback, load fallback,
//  and the platform asymmetry that decides whether the fallback is live.
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

/// Removes every generic-password item at `service`/`account`, synchronizable
/// or not.
///
/// One delete is enough: `kSecAttrSynchronizableAny` spans both kinds, which is
/// exactly what `KeychainPlatformAsymmetryTests` asserts on the read side. This
/// matches `DeviceFingerprintTests`' `deleteRealKeychainFingerprint`, the other
/// real-Keychain cleanup in this target.
private func deleteKeychainItems(service: String, account: String) {
    SecItemDelete([
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
    ] as CFDictionary)
}

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
    //    One qualification, added by iOS#1037 and easy to miss: on the macOS
    //    host the *synchronizable* add does NOT pass — it needs an
    //    `application-identifier` entitlement there just as it does in the
    //    Simulator. The two `synchronizable: true` save tests below pass only
    //    because `save()` retries without the flag, and that retry lands in
    //    the login Keychain. Delete the retry and they go red on the macOS
    //    host while staying skipped in the Simulator. `save()` explains the
    //    mechanism; `KeychainPlatformAsymmetryTests`, at the bottom of this
    //    file, asserts it.
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
        "A synchronizable save round-trips through load()",
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

        // The assertions below pass whichever add succeeded, so this test on
        // its own does not establish which branch ran — hence its name. It is
        // under-specified, not covering a dead branch: on the macOS host it
        // runs on, every `synchronizable: true` save does reach the retry (the
        // sync add fails -34018, the retry succeeds).
        //
        // `KeychainPlatformAsymmetryTests` pins that down, and needs no seam
        // to do it: it asserts the item this save leaves behind is matched by
        // a non-synchronizable-only query, which is true only if the retry
        // wrote it. `DeviceFingerprintTests`' "Sync add failure falls back to
        // non-synchronizable add" covers the sibling storage's branch by
        // injection, via `MockKeychainOperations`.
        let storage = makeStorage(synchronizable: true)
        try storage.save(session)

        // Load should find the item regardless of how it was saved
        let loaded = try storage.load()
        #expect(loaded?.jwt == session.jwt)
        #expect(loaded?.userId == session.userId)

        try storage.delete()
    }

    @Test(
        "A synchronizable save persists across instances",
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

        // Save with synchronizable=true. As above, this does not itself
        // establish which add succeeded — only that whatever was written
        // survives into a fresh instance, which is the app-relaunch case it
        // stands in for. On the macOS host it is the retry's item that
        // survives; see `KeychainPlatformAsymmetryTests`.
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
        // An arbitrary well-formed group, NOT the production one. This test
        // is about query construction, so the value only has to round-trip.
        // Pinning the real group here would be actively harmful: it varies by
        // target (see KeychainAccessGroup), and a literal that looks
        // authoritative is what #996 was built out of.
        let group = "ABCDE12345.group.example.test"
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
        let group = "ABCDE12345.group.example.test"
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
        deleteKeychainItems(service: testService, account: testAccount)
    }
}

// MARK: - Platform Asymmetry

private let regimeService = "org.wxyc.app.auth.test.regime"
private let regimeAccount = "anonymous-session-regime"

/// How this host's Keychain answers the two adds `KeychainTokenStorage.save()`
/// makes, probed once against a throwaway service.
///
/// Probed rather than assumed: the regime follows the running process's
/// entitlements, not its platform, so `#if os(...)` would classify the host
/// wrongly wherever the two diverge — an entitled macOS app and an unentitled
/// `swift test` process are the same OS and different regimes.
///
/// It exists because "the statuses that break a synchronizable add reject the
/// local add identically" holds on iOS and fails on macOS, where the flag
/// selects the Keychain backend rather than an attribute of the item. See
/// `KeychainTokenStorage.save()` for the mechanism (iOS#1035, iOS#1037).
private enum HostKeychainAdds {

    /// The two statuses, and the three regimes they can form.
    struct Regime: Sendable {
        let sync: OSStatus
        let local: OSStatus

        /// An entitled process: both adds land, so the retry never runs.
        ///
        /// This is every shipping build, on every platform — an iOS device
        /// (the 294-device fleet in `save()`'s comment) and equally a signed
        /// macOS/Catalyst build, which carries an `application-identifier` by
        /// way of `keychain-access-groups` in `WXYC.entitlements`.
        var bothSucceed: Bool { sync == errSecSuccess && local == errSecSuccess }

        /// One Keychain, and it rejected both adds — so the retry cannot
        /// salvage the write. The unentitled iOS Simulator test bundle, where
        /// both fail `errSecMissingEntitlement`.
        ///
        /// Deliberately not `local == sync`. That the two statuses are equal
        /// is an iOS observation, not the property being classified: a locked
        /// login Keychain on a headless runner answers -34018 and -25308, and
        /// that is this regime for every purpose the taxonomy serves.
        var retryCannotHelp: Bool { sync != errSecSuccess && local != errSecSuccess }

        /// Split backends, and only the local one is reachable: an unentitled
        /// macOS process, which is what `swift test` runs in. The retry is the
        /// only reason the write lands.
        var onlyLocalSucceeds: Bool { sync != errSecSuccess && local == errSecSuccess }

        /// Whether this host is one of the three regimes above. `false` means
        /// this file's account of the Keychain is incomplete — see
        /// `hostRegimeIsClassified`.
        ///
        /// Total except `(success, failure)`: a synchronizable add that lands
        /// where a local one is refused inverts the mechanism documented in
        /// `save()`, and deserves to fail loudly rather than be absorbed.
        var isClassified: Bool { bothSucceed || retryCannotHelp || onlyLocalSucceeds }

        /// Whether a local-only item can be written here at all. The
        /// precondition for any test that needs one to match against.
        var canWriteLocalItem: Bool { local == errSecSuccess }
    }

    /// Probed once per process. `static let` is lazy and thread-safe, and the
    /// probe writes only to a UUID-suffixed service it then deletes, so it
    /// cannot collide with either suite's items.
    static let regime: Regime = {
        // Fixed, not UUID-suffixed. A UUID would put every probe outside both
        // of this file's fixed-name sweeps, so a process killed between the
        // adds and the delete below would orphan an item that no later run
        // could find by name. A fixed name is self-healing: the pre-sweep
        // clears any such leftover, which also preserves the meaning of an
        // errSecDuplicateItem result rather than masking it.
        let service = "\(regimeService).probe"

        func attributes(synchronizable: Bool) -> [String: Any] {
            var attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: regimeAccount,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecValueData as String: Data("probe".utf8)
            ]
            if synchronizable {
                attributes[kSecAttrSynchronizable as String] = true
            }
            return attributes
        }

        // Sweep before as well as after, so a leftover from a killed run
        // cannot answer errSecDuplicateItem and be read as a regime.
        deleteKeychainItems(service: service, account: regimeAccount)

        // Synchronizable first, matching `save()`. The outcome does not depend
        // on the order, but matching it keeps the probe honest.
        let sync = SecItemAdd(attributes(synchronizable: true) as CFDictionary, nil)
        let local = SecItemAdd(attributes(synchronizable: false) as CFDictionary, nil)

        deleteKeychainItems(service: service, account: regimeAccount)

        return Regime(sync: sync, local: local)
    }()
}

/// Pins down whether `save()`'s local-only retry is dead code or load-bearing,
/// which iOS#1037 asks and which the fleet data cannot answer because every
/// row of it is from iOS.
///
/// Deliberately carries no `WXYC_SKIP_KNOWN_FLAKES` trait. The taxonomy test
/// is meaningful in every regime including the iOS Simulator's, and the
/// load-bearing test gates itself on the regime, so copying the skip here
/// would only hide both — see the note on that trait in the suite above.
@Suite("Keychain platform asymmetry", .serialized)
struct KeychainPlatformAsymmetryTests {

    let mockAnalytics = MockStructuredAnalytics()

    init() {
        deleteRegimeItems()
    }

    /// Asserts the gate rather than assuming it, so the gated test below
    /// cannot go quietly vacuous on a host nobody anticipated. A fourth regime
    /// would mean this file's account of the platforms is incomplete, and the
    /// failure message carries the two statuses needed to extend it.
    @Test("The host falls in one of the three known add regimes")
    func hostRegimeIsClassified() {
        let regime = HostKeychainAdds.regime
        #expect(
            regime.isClassified,
            """
            Unclassified Keychain regime: synchronizable add returned \(regime.sync), \
            local add returned \(regime.local). The axis is the process's entitlements, \
            not its platform. The three known regimes are: entitled (both succeed); \
            unentitled with one Keychain, i.e. the iOS Simulator bundle (both fail); \
            unentitled with split backends, i.e. an unentitled macOS process (sync \
            fails, local succeeds). See iOS#1037.
            """
        )
    }

    /// The assertion `KeychainTokenStorageTests`' two round-trip cases cannot
    /// make: that the item on disk is the one the *retry* wrote.
    ///
    /// A query that omits `kSecAttrSynchronizable` matches only
    /// non-synchronizable items, so finding the session through it proves the
    /// second `SecItemAdd` is what persisted it. Deleting the retry from
    /// `save()` turns this red under `swift test` on macOS — which is the
    /// point: it is the regression test iOS#1037 needs before anyone removes
    /// the branch on the strength of iOS-only telemetry.
    @Test(
        "Where only the local add succeeds, save()'s retry is what persists the session",
        .disabled(
            if: !HostKeychainAdds.regime.onlyLocalSucceeds,
            "Host is not in the sync-fails/local-succeeds regime, so the retry is not the branch under test here."
        )
    )
    func retryIsWhatPersistsTheSession() throws {
        let session = AuthSession(
            sessionToken: "regime-session", jwt: "regime-jwt",
            userId: "regime-user",
            createdAt: Date(),
            expiresAt: nil
        )

        let storage = KeychainTokenStorage(
            service: regimeService,
            account: regimeAccount,
            accessGroup: nil,
            synchronizable: true,
            analytics: mockAnalytics
        )

        // Assert the pre-state, or this test can pass without the retry ever
        // running. `save()` tries `SecItemUpdate` over `baseQuery()` first,
        // and that query carries `kSecAttrSynchronizableAny` — so a stale
        // local-only item at this service would be UPDATED, `save()` would
        // return before reaching either add, and the non-synchronizable query
        // below would still find it. `init()`'s sweep is what normally
        // guarantees this, but it discards its `SecItemDelete` status, so a
        // silent sweep failure would otherwise leave this guard green forever.
        var preState = baseRegimeQuery()
        preState[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        #expect(
            SecItemCopyMatching(preState as CFDictionary, nil) == errSecItemNotFound,
            "Stale item at \(regimeService): save() would take the SecItemUpdate path and this test would not exercise the retry at all."
        )

        try storage.save(session)

        // `false`, not `kSecAttrSynchronizableAny`: this has to match ONLY the
        // non-synchronizable item, which is what makes the retry the thing
        // being proved rather than merely the thing that happened to run.
        var query = baseRegimeQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecAttrSynchronizable as String] = false
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #expect(status == errSecSuccess, "Non-synchronizable query did not find the saved session (status \(status)); save()'s retry is not what wrote it.")

        let data = try #require(result as? Data)
        let stored = try JSONDecoder.shared.decode(AuthSession.self, from: data)
        #expect(stored.jwt == session.jwt)
        #expect(stored.userId == session.userId)

        try storage.delete()
    }

    /// The read-side half of iOS#1037: `kSecAttrSynchronizableAny` matches
    /// non-synchronizable items, so `load()`'s primary query already finds
    /// anything `loadNonSynchronizable()` could. The issue's constraint that
    /// deleting that method "would orphan those sessions" rests on the
    /// opposite belief; this is the check that settles it.
    @Test(
        "kSecAttrSynchronizableAny matches a non-synchronizable item",
        .disabled(
            if: !HostKeychainAdds.regime.canWriteLocalItem,
            "Host cannot write a non-synchronizable item, so there is nothing to match."
        )
    )
    func synchronizableAnyMatchesNonSynchronizableItems() throws {
        let session = AuthSession(
            sessionToken: "any-session", jwt: "any-jwt",
            userId: "any-user",
            createdAt: Date(),
            expiresAt: nil
        )

        let addStatus = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: regimeService,
            kSecAttrAccount as String: regimeAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: try JSONEncoder().encode(session)
        ] as CFDictionary, nil)
        try #require(addStatus == errSecSuccess)

        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: regimeService,
            kSecAttrAccount as String: regimeAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ] as CFDictionary, &result)

        #expect(status == errSecSuccess, "kSecAttrSynchronizableAny failed to match a non-synchronizable item (status \(status)).")
        let data = try #require(result as? Data)
        #expect(try JSONDecoder.shared.decode(AuthSession.self, from: data).jwt == session.jwt)

        deleteRegimeItems()
    }

    /// Class, service and account for the asymmetry suite's items. Callers add
    /// the `kSecAttrSynchronizable` value they mean — which is the whole point
    /// here, so it is deliberately absent rather than defaulted.
    private func baseRegimeQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: regimeService,
            kSecAttrAccount as String: regimeAccount
        ]
    }

    private func deleteRegimeItems() {
        deleteKeychainItems(service: regimeService, account: regimeAccount)
    }
}
