//
//  WXYCAppShortcutsTests.swift
//  WXYC
//
//  Unit tests for WXYCAppShortcuts (Intents.swift). AppShortcut discovery
//  happens at build time via the App Intents compiler plugin, so these tests
//  guard what we can observe at runtime: that `appShortcuts` resolves without
//  crashing and, specifically, that OpenPlaycut (#428) and OpenConcert (#624)
//  are each registered with multiple invocation phrases. `AppShortcut`
//  type-erases both its intent and its phrases and exposes no public
//  accessors, so the per-intent assertions reflect into the value rather than
//  trusting a bare shortcut count — any Nth intent would satisfy a count
//  check. #641 re-examined this reflection walk for SDK fragility and,
//  finding no more-robust public alternative, kept it with an expanded
//  rationale next to `reflectionContains` below plus a metatype-aware match.
//
//  Also covers WXYCApp.makeSiriIntentInteraction() (#740): the legacy SiriKit
//  donation built by WXYCApp.donateSiriIntent(), unrelated to the App Intents
//  shortcuts above but colocated here as this file's other Siri-adjacent
//  WXYCApp coverage.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Intents
import Testing
@testable import WXYC
@testable import WXYCIntents

@Suite("WXYCAppShortcuts")
struct WXYCAppShortcutsTests {
    /// The discoverable shortcuts we register: WhatsPlayingOnWXYC, PlayWXYC,
    /// MakeARequest, OpenPlaycut (#428), OpenConcert (#624), ToursNearMe
    /// (OT-C2), and AddConcertToCalendarIntent (OT-C7). Unlike
    /// `openPlaycutIntentIsRegistered()` and `openConcertIntentIsRegistered()`
    /// below, this count isn't SDK-fragile — it only changes when someone
    /// deliberately adds or removes an `AppShortcut` in `WXYCAppShortcuts`,
    /// not when Apple restructures `AppShortcut`'s private storage. Bump this
    /// count (and the test name) whenever you add or remove a shortcut.
    @Test("appShortcuts registers exactly seven shortcuts")
    func registersSevenShortcuts() {
        #expect(WXYCAppShortcuts.appShortcuts.count == 7)
    }

    @Test("OpenPlaycut (#428) is specifically registered, not merely a 4th intent")
    func openPlaycutIntentIsRegistered() {
        // AppShortcut type-erases its intent and phrases and exposes no public
        // accessors, so a bare count check can't tell OpenPlaycut apart from
        // any other intent. Reflect into each shortcut for the OpenPlaycut
        // instance the AppShortcut stores. (The phrase list itself is validated
        // at build time by the App Intents compiler plugin — an AppShortcut with
        // no phrases won't compile — so runtime phrase-count assertions would
        // only add brittleness against Apple's private storage layout.)
        #expect(
            WXYCAppShortcuts.appShortcuts.contains { reflectionContains(OpenPlaycut.self, in: $0) },
            "No AppShortcut is registered for the OpenPlaycut intent (#428)"
        )
    }

    @Test("OpenConcert (#624) is specifically registered, not merely a 5th intent")
    func openConcertIntentIsRegistered() {
        // Mirrors openPlaycutIntentIsRegistered() above for the On Tour
        // OpenConcert shortcut (#624, part of the Spotlight epic #619).
        #expect(
            WXYCAppShortcuts.appShortcuts.contains { reflectionContains(OpenConcert.self, in: $0) },
            "No AppShortcut is registered for the OpenConcert intent (#624)"
        )
    }
}

// MARK: - Siri Donation Interaction Tests (#740)

/// Regression coverage for #740 / Sentry IOS-3M (`CGImageRef.overlay`), IOS-14,
/// and IOS-19 (`WXYCApp.donateSiriIntent`): a >2s app hang caused by
/// `WXYCApp.init()` synchronously compositing `UIImage.placeholder`
/// (CoreImage/Metal) on the main thread while building the legacy SiriKit
/// donation. `donateSiriIntent()` now defers that work to a `Task` inside a
/// `nonisolated` function; see `WXYCAppDonationEscapesMainActorTests` below
/// for the runtime proof that the `Task` actually runs off the main actor —
/// this module's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means merely
/// calling these functions from a non-`@MainActor` test context (as this
/// suite does) proves nothing about where they *actually* run, since
/// `nonisolated` code is callable from anywhere regardless of isolation.
@Suite("WXYCApp Siri donation interaction")
struct WXYCAppSiriIntentInteractionTests {
    @Test("makeSiriIntentInteraction builds an INPlayMediaIntent")
    func buildsPlayMediaIntent() async {
        let interaction = WXYCApp.makeSiriIntentInteraction()
        #expect(interaction.intent is INPlayMediaIntent)
    }

    @Test("makeSiriIntentInteraction's media item carries the composited placeholder artwork")
    func mediaItemCarriesPlaceholderArtwork() async {
        let interaction = WXYCApp.makeSiriIntentInteraction()
        let mediaItem = (interaction.intent as? INPlayMediaIntent)?.mediaItems?.first

        #expect(mediaItem?.artwork != nil, "Siri donation artwork must still be present after moving placeholder compositing off the launch path")
    }
}

/// The decisive regression check for #740: proves `donateSiriIntent()`'s real
/// `Task` — the one `WXYCApp.init()` actually schedules — runs off the main
/// actor at runtime, not just that its callees compile from a non-`@MainActor`
/// context (see the note on `WXYCAppSiriIntentInteractionTests` above for why
/// that alone is not sufficient under this module's default actor isolation).
///
/// `donateSiriIntent(isolationProbe:)`'s probe parameter exists solely for
/// this test: it captures `#isolation` — the *actual* isolation of the
/// `Task`'s closure — as its very first statement and reports it back
/// through a checked continuation, deterministically suspending this test
/// until the real, unstructured `Task` actually runs (no `Task.sleep`
/// guessing, no crash-based assertion). `#isolation` is `nil` for a
/// non-isolated context and non-nil (`MainActor.shared`) if the `Task` is
/// main-actor isolated, so this fails as an ordinary assertion — not a
/// process crash — if the isolation ever regresses.
@Suite("WXYCApp Siri donation escapes the main actor (#740)")
@MainActor
struct WXYCAppDonationEscapesMainActorTests {
    @Test("donateSiriIntent's Task is not main-actor isolated")
    func donationTaskIsNotMainActorIsolated() async {
        let isolation: (any Actor)? = await withCheckedContinuation { continuation in
            WXYCApp.donateSiriIntent(isolationProbe: { isolation in
                continuation.resume(returning: isolation)
            })
        }

        #expect(isolation == nil, "donateSiriIntent()'s Task must not be main-actor isolated, or its UIImage.placeholder compositing hangs the main thread again (#740)")
    }
}

// MARK: - Reflection helpers

// WXYC/wxyc-ios-64#641: this reflection walk is a deliberate, documented
// retain — not an oversight — because no more-robust public alternative
// exists. Verified directly against the installed AppIntents.framework's
// public interface (Xcode 26 SDK,
// AppIntents.framework/Modules/AppIntents.swiftmodule/*.swiftinterface):
// `AppShortcut` has exactly two initializers and zero public stored
// properties or accessors, so the intent and phrases it's constructed with
// are unrecoverable once boxed. `AppShortcutsProvider` doesn't expose
// per-shortcut metadata either — only the `appShortcuts` array itself and an
// unrelated `shortcutTileColor`. Asserting on `OpenPlaycut`'s own
// `AppIntent`/`OpenIntent` conformance instead (one option raised on #641)
// would be a *different*, weaker claim: it proves the type is intent-shaped,
// not that `WXYCAppShortcuts.appShortcuts` actually registered an
// `AppShortcut` for it, so it can't substitute for this check.
//
// SDK-fragility rationale: this walk depends on `AppShortcut` making the
// intent reachable somewhere in its `Mirror` child graph, either as an
// instance or as a metatype — `reflectionContains` checks both (`value is T`
// and `value is T.Type`) so a future SDK that boxes the intent as
// `OpenPlaycut.self` rather than `OpenPlaycut()` still passes. What it can't
// survive is a storage change that erases the type identity entirely, e.g.
// hashing the intent into an opaque token before storing it.
//
// If a future SDK bump makes `openPlaycutIntentIsRegistered()` fail against a
// known-good build: dump `Mirror(reflecting:)` recursively over
// `WXYCAppShortcuts.appShortcuts` to see the new storage shape, then extend
// `reflectionContains` to recognize it (a new label, a wrapper type, an
// `ObjectIdentifier(OpenPlaycut.self)`-keyed token, etc.). If no reachable
// signal survives at all, the documented fallback is to drop
// `openPlaycutIntentIsRegistered()` and rely solely on
// `registersSevenShortcuts()` above, noting the loss of per-intent specificity
// in that test's doc comment.

/// Recursively searches `value`'s reflection tree for a stored value whose
/// dynamic type is `type` (the intent instance an `AppShortcut` stores),
/// matching by instance cast, metatype cast (`type` stored as `T.self`
/// rather than `T()`), or dynamic-type name so a type-erased wrapper still
/// counts. Depth-bounded so a malformed graph can't loop.
private func reflectionContains<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> Bool {
    if value is T { return true }
    if value is T.Type { return true }
    if String(describing: Swift.type(of: value)) == String(describing: type) { return true }
    guard depth < 8 else { return false }
    for child in Mirror(reflecting: value).children where reflectionContains(type, in: child.value, depth: depth + 1) {
        return true
    }
    return false
}
