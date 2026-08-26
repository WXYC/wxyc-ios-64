//
//  KeychainAccessGroup.swift
//  AppServices
//
//  Derives the Keychain access group this process may actually use by asking
//  the Keychain, instead of transcribing a build-time variable into source.
//
//  Created by Jake Bromberg on 08/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Security

// MARK: - Probe Seam

/// Narrow seam over the Keychain so resolution can be tested without an
/// entitled, signed host.
///
/// Deliberately returns the group *the Keychain assigned*, not a prefix or a
/// team identifier. Every value that crosses this boundary is therefore one
/// the running process is provably entitled to, which is the property that
/// makes ``KeychainAccessGroup`` unable to reintroduce issue #996.
internal protocol KeychainAccessGroupProbe: Sendable {

    /// The access group the Keychain assigns to an item added with no explicit
    /// `kSecAttrAccessGroup`, or `nil` when it cannot be determined.
    func defaultAccessGroup() -> String?
}

// MARK: - Resolution

/// The Keychain access group shared by the targets that can reach it.
///
/// ## Why this is resolved and not written down
///
/// A Keychain access group is `<App ID prefix>.<group name>`, and the App ID
/// prefix is **not** the Team ID. It equals the Team ID only for App IDs
/// created after mid-2011. `org.wxyc.iphoneapp` predates that: it is seeded
/// `Q43UJWVEZV` while the team is `92V374HC38`, so the shipping app is
/// entitled to `Q43UJWVEZV.group.wxyc.iphone` and to nothing else.
///
/// The entitlement plists have always been right — they say
/// `$(AppIdentifierPrefix)group.wxyc.iphone`, which Xcode expands correctly per
/// target. The defect in #996 was that Swift cannot see that build variable, so
/// the value was hand-copied into a constant, and it was copied with the Team
/// ID. Every Keychain read and write in 3.2, 3.2.1 and 3.2.2 therefore failed
/// with `errSecMissingEntitlement (-34018)` — 7,062 events across 505 people in
/// 30 days, with no other status ever observed. No session and no device
/// fingerprint has ever persisted across a launch.
///
/// A pinned constant could not have caught this: the test that guarded it
/// asserted one hand-written literal against another copy of the same literal,
/// which is true for any value including the wrong one. So the fix is not a
/// better constant — it is not having one. The prefix now comes from the
/// Keychain at runtime; only the group *name*, which does not vary by target or
/// signing configuration, stays in source.
///
/// - Note: `$(TeamIdentifierPrefix)` is Apple's documented remedy for this
///   split and does **not** work here. A profile's `keychain-access-groups`
///   derives from the App ID's own prefix, so a `Q43UJWVEZV`-seeded App ID can
///   never be granted a `92V374HC38.*` group. Verified by building Release for
///   device with `-allowProvisioningUpdates`: Xcode consulted the portal and
///   still failed with "Provisioning profile ... doesn't match the entitlements
///   file's value for the keychain-access-groups entitlement". Do not retry it.
///
/// - Important: **None of this can be exercised in the Simulator.** The project
///   sets `CODE_SIGNING_ALLOWED[sdk=*simulator*] = NO`, so simulator builds
///   embed no entitlements blob at all, and `errSecMissingEntitlement` is
///   documented as firing when the client has "neither application-identifier
///   nor keychain-access-group entitlements" — i.e. with or without
///   `kSecAttrAccessGroup`. Measured: a bare `SecItemAdd` carrying no access
///   group returns `-34018` in the Simulator, so ``SecItemAccessGroupProbe``
///   correctly resolves to `nil` there and the whole Keychain subsystem is
///   inert. This is also what the Simulator-origin `-34018` rows in PostHog
///   are (`$device_model == "arm64"`); they are unrelated to the App ID prefix
///   defect and must be excluded from any reading of the fix. Device-side
///   confirmation is `fingerprint_mode_resolved_event` ceasing to report
///   `mode = failed`.
public enum KeychainAccessGroup {

    /// The group name declared in every `keychain-access-groups` entitlement,
    /// minus the per-target prefix.
    ///
    /// This half is safe to keep in source precisely because it is the half
    /// that does not vary: `WXYC.entitlements`, `WXYCDebug.entitlements` and
    /// `ShareExtension.entitlements` all spell it identically, and no build
    /// setting rewrites it.
    internal static let groupName = "group.wxyc.iphone"

    /// The access group to scope Keychain items to, or `nil` to use the
    /// process default.
    ///
    /// `nil` is a working answer, not a failure: omitting `kSecAttrAccessGroup`
    /// makes writes land in the process's default group and makes reads search
    /// every group the process is entitled to. It is what unsigned Simulator
    /// builds get, and it is strictly better than naming a group that might be
    /// wrong.
    public static func resolve() -> String? {
        resolve(probe: SecItemAccessGroupProbe())
    }

    internal static func resolve(probe: some KeychainAccessGroupProbe) -> String? {
        guard let group = probe.defaultAccessGroup() else { return nil }

        // Echo the probe's answer back only when it is one of ours. Anything
        // else means this process has no wxyc group — an unsigned Simulator
        // build, or a target whose entitlement omits `keychain-access-groups`
        // — and the honest answer there is `nil`.
        //
        // Suffix-matching on ".<groupName>" rather than deriving from the
        // first dot-component is load-bearing. A bundle-derived default such
        // as `org.wxyc.iphoneapp` would otherwise yield `org.group.wxyc.iphone`
        // — a group nothing on earth is entitled to, which is #996 again in a
        // new costume.
        guard group.hasSuffix(".\(groupName)") else { return nil }

        return group
    }
}

// MARK: - Production Probe

/// Asks the Keychain which access group it hands an unqualified item.
///
/// Adds a throwaway generic-password item with no `kSecAttrAccessGroup`, reads
/// the `kSecAttrAccessGroup` the Keychain stamped on it, and deletes it again.
/// The add is what makes this authoritative: the returned group is one the
/// Keychain itself chose for this process, so it cannot name something the
/// process lacks the entitlement for.
internal struct SecItemAccessGroupProbe: KeychainAccessGroupProbe {

    /// Distinct from every real item's service so a probe can never collide
    /// with, read, or delete a session token or a device fingerprint.
    private static let service = "org.wxyc.app.access-group-probe"
    private static let account = "probe"

    func defaultAccessGroup() -> String? {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]

        // Add first, then read back. `SecItemAdd`'s own `kSecReturnAttributes`
        // dictionary does not reliably carry `kSecAttrAccessGroup` — verified
        // in the iOS Simulator, where asking it directly yields nil even
        // though the item is added fine. The authoritative read is
        // `SecItemCopyMatching` against the stored item.
        var addAttributes = identity
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)

        // `errSecDuplicateItem` means a previous launch was interrupted
        // between the add and the delete. That item answers the same
        // question, so read it rather than giving up.
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            return nil
        }

        defer {
            SecItemDelete(identity as CFDictionary)
        }

        var readQuery = identity
        readQuery[kSecReturnAttributes as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(readQuery as CFDictionary, &result) == errSecSuccess,
              let stored = result as? [String: Any],
              let group = stored[kSecAttrAccessGroup as String] as? String else {
            return nil
        }

        return group
    }
}
