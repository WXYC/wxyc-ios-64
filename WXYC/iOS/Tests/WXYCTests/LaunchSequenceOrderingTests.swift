//
//  LaunchSequenceOrderingTests.swift
//  WXYC
//
//  Pins the one ordering constraint in `WXYCApp.init()` that fails silently:
//  analytics must be started before anything captures an event, because
//  PostHog drops pre-`setup` captures rather than buffering them
//  (WXYC/wxyc-ios-64#1002).
//
//  Source-scanning rather than behavioural, for the same reason the defect
//  survived four months: the failure has no runtime signal. `PostHogSDK`
//  swallows the call, `capture` returns void, and the only evidence is an
//  event that never arrives in a project nobody was watching. There is no
//  seam to assert against — `AnalyticsBootstrap.start` writes to a private
//  flag inside a vendored singleton — so the invariant is checked where it is
//  actually expressed: the order of two statements in one initializer. The
//  precedent for reading source in a test is
//  `AppIntentsDependenciesTests.swift`, including its guard against passing
//  vacuously when the file cannot be read.
//
//  Created by Jake Bromberg on 08/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing

@Suite("Launch sequence ordering")
struct LaunchSequenceOrderingTests {

    /// The code lines of `WXYC/iOS/WXYCApp.swift`, located relative to this
    /// file so the test moves with the target rather than depending on a
    /// bundle resource.
    ///
    /// Comment lines are dropped before matching. Both call sites are now
    /// documented with comments that name the very calls this test searches
    /// for, so a whole-string search finds the prose above the code and
    /// reports the opposite of the truth — this test failed against the fixed
    /// file until it learned to skip comments.
    private static var appCodeLines: [String] {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // WXYCTests
                .deletingLastPathComponent()  // Tests
                .deletingLastPathComponent()  // iOS
                .appendingPathComponent("WXYCApp.swift")
            return try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") }
        }
    }

    @Test("Analytics is started before MusicShareKit is configured")
    func analyticsStartsBeforeMusicShareKitIsConfigured() throws {
        let lines = try Self.appCodeLines

        // Both must be present. Without this, renaming either call would make
        // the ordering assertion below pass by finding nothing at all — the
        // exact way a source-scanning test rots into a no-op.
        let analytics = try #require(
            lines.firstIndex(where: { $0.contains("AppBootstrap.setUpAnalytics()") }),
            "AppBootstrap.setUpAnalytics() is no longer called from WXYCApp.swift. If the launch sequence moved, move this test with it rather than deleting it — see WXYC/wxyc-ios-64#1002."
        )
        let configure = try #require(
            lines.firstIndex(where: { $0.contains("MusicShareKit.configure(") }),
            "MusicShareKit.configure( is no longer called from WXYCApp.swift. If the launch sequence moved, move this test with it rather than deleting it — see WXYC/wxyc-ios-64#1002."
        )

        #expect(
            analytics < configure,
            """
            MusicShareKit.configure(...) runs before AppBootstrap.setUpAnalytics().

            configure(...) eagerly resolves the device fingerprint and captures \
            fingerprint_mode_resolved_event (and, on failure, \
            device_fingerprint_init_failed_event). PostHogSDK.capture gates on a \
            private isEnabled() that only becomes true inside \
            AnalyticsBootstrap.start -> PostHogSDK.shared.setup, and it DISCARDS \
            calls made before then — it does not queue them. In that order both \
            events are silently dropped on every launch, and a zero reading for \
            either becomes evidence of nothing.

            Do not fix this by buffering pre-setup events. Start analytics first.
            """
        )
    }
}
