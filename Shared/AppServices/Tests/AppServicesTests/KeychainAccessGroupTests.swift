//
//  KeychainAccessGroupTests.swift
//  AppServices
//
//  Tests that the Keychain access group tracks the build-expanded Info.plist
//  value rather than a transcribed constant (issue #996).
//
//  Created by Jake Bromberg on 08/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import AppServices

/// The App ID prefix the production bundle `org.wxyc.iphoneapp` is seeded with.
/// It is **not** the Team ID.
private let productionPrefix = "Q43UJWVEZV"

/// The Team ID — which every WXYC App ID *except* the production one uses as
/// its prefix, and which #996 wrongly assumed the production one used too.
private let teamID = "92V374HC38"

@Suite("Keychain Access Group Resolution")
struct KeychainAccessGroupTests {

    /// Resolution is pure echo: whatever prefix this target's build expanded
    /// comes back unchanged.
    ///
    /// Parameterized over both prefixes on purpose — that is what pins the #996
    /// regression. No hardcoded constant can satisfy both rows, so a resolver
    /// that ignored its input and returned a literal fails here regardless of
    /// which literal it chose.
    @Test("echoes back whichever prefixed wxyc group the build declared",
          arguments: [productionPrefix, teamID])
    func echoesDeclaredGroup(prefix: String) {
        let declared = "\(prefix).\(KeychainAccessGroup.groupName)"

        #expect(KeychainAccessGroup.resolve(declared: declared) == declared)
    }

    /// Everything that is not a prefixed wxyc group resolves to `nil`, which
    /// means "use the process default" and works everywhere.
    ///
    /// The bare `group.wxyc.iphone` row is the load-bearing one: that is what
    /// `$(AppIdentifierPrefix)group.wxyc.iphone` expands to in an **unsigned**
    /// build, and simulator builds are unsigned by project policy
    /// (`CODE_SIGNING_ALLOWED[sdk=*simulator*] = NO`), so they hold no
    /// entitlements and can use no access group at all.
    @Test("refuses anything that is not a prefixed wxyc group", arguments: [
        nil,                                  // key absent from Info.plist
        "",                                   // key present but empty
        "group.wxyc.iphone",                  // unsigned build: empty prefix
        "92V374HC38.group.wxyc.iphone.other", // suffixed past the group name
        "92V374HC38.notgroup.wxyc.iphone",    // different group
        "org.wxyc.iphoneapp"                  // a bundle id, not a group
    ] as [String?])
    func refusesAnythingElse(declared: String?) {
        #expect(KeychainAccessGroup.resolve(declared: declared) == nil)
    }

    /// `AppConfiguration` must delegate rather than hold a literal of its own.
    ///
    /// Runs unconditionally and is red for any reintroduced constant, including
    /// the #996 one — unlike a `hasSuffix` shape check, which the #996 literal
    /// would have passed, and unlike an `if let` over a value that is `nil` in
    /// every environment this suite actually runs in.
    @Test("AppConfiguration delegates to the resolver")
    func appConfigurationDelegates() {
        #expect(AppConfiguration.keychainAccessGroup == KeychainAccessGroup.current)
    }
}
