//
//  KeychainAccessGroup.swift
//  AppServices
//
//  Reads the Keychain access group out of Info.plist, where the build system
//  expands the same variable the entitlement uses, instead of transcribing it.
//
//  Created by Jake Bromberg on 08/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The Keychain access group this target is entitled to, or `nil`.
///
/// ## Why this is read and not written down
///
/// A Keychain access group is `<App ID prefix>.<group name>`, and the App ID
/// prefix is **not** the Team ID. It equals the Team ID only for App IDs
/// created after mid-2011. `org.wxyc.iphoneapp` predates that: it is seeded
/// `Q43UJWVEZV` while the team is `92V374HC38`, so the shipping app is entitled
/// to `Q43UJWVEZV.group.wxyc.iphone` and to nothing else. Every *other* WXYC
/// App ID — the debug bundle, the widget, the Share Extension, the watch app —
/// was created recently enough that its prefix is the Team ID, which is why the
/// wrong value looked right in a debug build.
///
/// The entitlement plists have always been correct. They say
/// `$(AppIdentifierPrefix)group.wxyc.iphone`, which Xcode expands per target.
/// The defect in #996 was that the value was *also* hand-copied into a Swift
/// constant — with the Team ID — and every Keychain read and write in 3.2,
/// 3.2.1 and 3.2.2 failed with `errSecMissingEntitlement (-34018)`: 7,062 events
/// across 505 people in 30 days, no other status ever observed, no session and
/// no fingerprint ever persisting across a launch.
///
/// A pinned constant could not have caught this. The test that guarded it
/// asserted one hand-written literal against another copy of the same literal,
/// which is true for every value including the wrong one. So the fix is to stop
/// having a second copy: `Info.plist` carries
/// `$(AppIdentifierPrefix)group.wxyc.iphone`, the build system expands it from
/// the same variable that produces the entitlement, and this type reads the
/// result. Verified on a Release device build of `org.wxyc.iphoneapp`, whose
/// built `Info.plist` reads `Q43UJWVEZV.group.wxyc.iphone` — byte-identical to
/// the `keychain-access-groups` entitlement on the same binary.
///
/// - Note: `$(TeamIdentifierPrefix)` is Apple's documented remedy for a
///   prefix/Team ID split and does **not** work here. A provisioning profile's
///   `keychain-access-groups` derives from the App ID's own prefix, so a
///   `Q43UJWVEZV`-seeded App ID can never be granted a `92V374HC38.*` group;
///   building Release for device with `-allowProvisioningUpdates` fails at
///   signing. That is a fact about the *entitlement*, not about the variable —
///   `$(TeamIdentifierPrefix)` expands perfectly well in `Info.plist`, it is
///   just the wrong value to put there.
///
/// - Note: Only the main app declares the key today. The Share Extension
///   deliberately does not: `ShareExtension.entitlements` is referenced zero
///   times in `project.pbxproj` (#905), so that target holds no
///   `keychain-access-groups` entitlement at all, and handing it a group it is
///   not entitled to would reproduce #996 there. A missing key resolves to
///   `nil`, which is the safe default. Add the key in the same change that
///   wires the entitlement — see #1008 for the cross-target group question.
public enum KeychainAccessGroup {

    /// The `Info.plist` key carrying `$(AppIdentifierPrefix)group.wxyc.iphone`.
    internal static let infoPlistKey = "WXYCKeychainAccessGroup"

    /// The group name shared by every target's entitlement, minus the prefix.
    internal static let groupName = "group.wxyc.iphone"

    /// The access group to scope Keychain items to, or `nil` for the process
    /// default.
    ///
    /// `nil` is a working answer rather than a failure: omitting
    /// `kSecAttrAccessGroup` writes to the process's default group and reads
    /// across every group it is entitled to.
    public static let current: String? = resolve(
        declared: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
    )

    /// Validates a declared group, so tests can drive every case without a
    /// bundle. Plain value injection rather than a protocol seam, matching
    /// `BuildEnvironment.init(isDebugBuild:...)` in `Core`.
    internal static func resolve(declared: String?) -> String? {
        // A prefix is required, not merely a suffix match. In an unsigned build
        // `$(AppIdentifierPrefix)` expands to nothing, leaving the bare
        // `group.wxyc.iphone` — and simulator builds are unsigned by project
        // policy (`CODE_SIGNING_ALLOWED[sdk=*simulator*] = NO`), so they carry
        // no entitlements and can use no access group at all. Rejecting the
        // unprefixed form is what turns that into `nil` instead of a group
        // nothing is entitled to.
        guard let declared, declared.hasSuffix(".\(groupName)") else { return nil }
        return declared
    }
}
