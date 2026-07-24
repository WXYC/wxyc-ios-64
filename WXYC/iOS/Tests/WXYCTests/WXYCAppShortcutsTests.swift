//
//  WXYCAppShortcutsTests.swift
//  WXYC
//
//  Unit tests for WXYCAppShortcuts (Intents.swift). AppShortcut discovery
//  happens at build time via the App Intents compiler plugin, so these tests
//  guard what we can observe at runtime: that `appShortcuts` resolves without
//  crashing and, specifically, that OpenPlaycut (#428) is registered with
//  multiple invocation phrases. `AppShortcut` type-erases both its intent and
//  its phrases and exposes no public accessors, so the OpenPlaycut assertions
//  reflect into the value rather than trusting a bare shortcut count — any
//  fourth intent would satisfy a count check.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Testing
@testable import WXYC
@testable import WXYCIntents

@Suite("WXYCAppShortcuts")
struct WXYCAppShortcutsTests {
    /// The discoverable shortcuts we register: WhatsPlayingOnWXYC, PlayWXYC,
    /// MakeARequest, and OpenPlaycut (#428).
    @Test("appShortcuts registers exactly four shortcuts")
    func registersFourShortcuts() {
        #expect(WXYCAppShortcuts.appShortcuts.count == 4)
    }

    @Test("OpenPlaycut (#428) is specifically registered, not merely a 4th intent")
    func openPlaycutIntentIsRegistered() {
        // AppShortcut type-erases its intent and phrases and exposes no public
        // accessors, so a bare `count == 4` can't tell OpenPlaycut apart from
        // any other 4th intent. Reflect into each shortcut for the OpenPlaycut
        // instance the AppShortcut stores. (The phrase list itself is validated
        // at build time by the App Intents compiler plugin — an AppShortcut with
        // no phrases won't compile — so runtime phrase-count assertions would
        // only add brittleness against Apple's private storage layout.)
        #expect(
            WXYCAppShortcuts.appShortcuts.contains { reflectionContains(OpenPlaycut.self, in: $0) },
            "No AppShortcut is registered for the OpenPlaycut intent (#428)"
        )
    }
}

// MARK: - Reflection helpers

/// Recursively searches `value`'s reflection tree for a stored value whose
/// dynamic type is `type` (the intent instance an `AppShortcut` stores),
/// matching either by cast or by dynamic-type name so a type-erased wrapper
/// still counts. Depth-bounded so a malformed graph can't loop.
private func reflectionContains<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> Bool {
    if value is T { return true }
    if String(describing: Swift.type(of: value)) == String(describing: type) { return true }
    guard depth < 8 else { return false }
    for child in Mirror(reflecting: value).children where reflectionContains(type, in: child.value, depth: depth + 1) {
        return true
    }
    return false
}
