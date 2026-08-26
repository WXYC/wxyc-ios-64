//
//  KeychainAccessGroupTests.swift
//  AppServices
//
//  Tests that the Keychain access group is derived from the running process's
//  own entitlement rather than transcribed from a build setting (issue #996).
//
//  Created by Jake Bromberg on 08/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import AppServices

/// The App ID prefix the production bundle `org.wxyc.iphoneapp` is actually
/// seeded with. It is **not** the Team ID — see the suite comment below.
private let productionPrefix = "Q43UJWVEZV"

/// The Team ID, which every WXYC App ID *except* the production one uses as
/// its prefix.
private let teamID = "92V374HC38"

@Suite("Keychain Access Group Resolution")
struct KeychainAccessGroupTests {

    // MARK: - Resolution

    /// The production case, and the whole point of #996.
    ///
    /// `org.wxyc.iphoneapp` is a legacy App ID whose prefix (`Q43UJWVEZV`)
    /// differs from the Team ID (`92V374HC38`), so the app is entitled to
    /// `Q43UJWVEZV.group.wxyc.iphone` and nothing else. The old code asked for
    /// the Team ID group and got `errSecMissingEntitlement (-34018)` on every
    /// read and write, on every device, for the entire 3.2 line.
    @Test("resolves the production app's group from its own App ID prefix")
    func resolvesProductionPrefix() {
        let probe = StubProbe(defaultGroup: "\(productionPrefix).group.wxyc.iphone")

        #expect(KeychainAccessGroup.resolve(probe: probe) == "Q43UJWVEZV.group.wxyc.iphone")
    }

    /// Non-vacuity guard for the test above.
    ///
    /// A resolver that ignored the probe and returned the old hardcoded
    /// constant would still satisfy every *other* assertion in this suite that
    /// happens to use a Team-ID-prefixed group. This one fails for that
    /// resolver and only for that resolver, so it is what proves the suite is
    /// actually exercising the #996 regression.
    @Test("never substitutes the Team ID for the App ID prefix")
    func neverSubstitutesTeamID() {
        let probe = StubProbe(defaultGroup: "\(productionPrefix).group.wxyc.iphone")

        #expect(KeychainAccessGroup.resolve(probe: probe) != "\(teamID).group.wxyc.iphone")
    }

    /// The extension case. Every WXYC App ID other than the production bundle
    /// was created recently enough that its prefix *is* the Team ID, so the
    /// same resolver has to hand back a different group in those processes.
    @Test("resolves an extension's group from its own App ID prefix")
    func resolvesExtensionPrefix() {
        let probe = StubProbe(defaultGroup: "\(teamID).group.wxyc.iphone")

        #expect(KeychainAccessGroup.resolve(probe: probe) == "92V374HC38.group.wxyc.iphone")
    }

    // MARK: - Refusal

    /// Unsigned Simulator builds carry no entitlements at all, so the Keychain
    /// assigns a bundle-derived default group rather than one of ours. Echoing
    /// it back would be harmless, but *deriving* a group from its first
    /// dot-component would invent `org.group.wxyc.iphone` — a group nothing is
    /// entitled to, reproducing #996 in a new place. Refuse instead: `nil`
    /// means "use the process default", which works everywhere.
    @Test("refuses a default group that is not one of ours")
    func refusesForeignGroup() {
        let probe = StubProbe(defaultGroup: "org.wxyc.iphoneapp")

        #expect(KeychainAccessGroup.resolve(probe: probe) == nil)
    }

    @Test("refuses a group whose name merely contains ours", arguments: [
        "\(teamID).group.wxyc.iphone.other",
        "\(teamID).notgroup.wxyc.iphone",
        "group.wxyc.iphone",
    ])
    func refusesNearMiss(defaultGroup: String) {
        let probe = StubProbe(defaultGroup: defaultGroup)

        #expect(KeychainAccessGroup.resolve(probe: probe) == nil)
    }

    /// A failed probe must not be papered over with a guess. `nil` degrades to
    /// the process's default access group, which is always usable; a guessed
    /// group is exactly what #996 was.
    @Test("returns nil when the probe cannot determine a group")
    func returnsNilWhenProbeFails() {
        #expect(KeychainAccessGroup.resolve(probe: StubProbe(defaultGroup: nil)) == nil)
    }

    // MARK: - Wiring

    /// `AppConfiguration` must not reintroduce a literal. This asserts on the
    /// *shape* of what it exposes rather than a value, because the correct
    /// value differs per target and per signing configuration — which is
    /// precisely why the constant it replaced could never have been right
    /// everywhere.
    @Test("AppConfiguration exposes either a wxyc group or nil, never a foreign one")
    func appConfigurationExposesOwnGroupOrNil() {
        if let group = AppConfiguration.keychainAccessGroup {
            #expect(group.hasSuffix(".group.wxyc.iphone"))
        }
    }
}

// MARK: - Test Double

private struct StubProbe: KeychainAccessGroupProbe {
    let defaultGroup: String?

    func defaultAccessGroup() -> String? { defaultGroup }
}
