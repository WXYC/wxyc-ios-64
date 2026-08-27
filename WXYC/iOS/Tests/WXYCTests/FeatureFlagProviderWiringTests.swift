//
//  FeatureFlagProviderWiringTests.swift
//  WXYC
//
//  Pins that both production `MusicShareKit.configure(...)` call sites pass a
//  non-nil `featureFlagProvider` (#1012). A missing provider makes
//  `RequestLineAuthFeature.isEnabled(...)` take its step-3 branch on every
//  call, which now captures `source: .unwired` rather than returning `false`
//  silently — but the right fix is to keep the provider wired in the first
//  place, and this is the direct test for that: WXYC/wxyc-ios-64#385 wired it
//  in `caf413388` and then sat unshipped on master for nearly three months
//  with nothing catching a regression.
//
//  The two call sites need different techniques, not the same one.
//  `WXYCTests` is a HOSTED target (`TEST_HOST = WXYC.app`), so by the time
//  any test in this file runs, `WXYCApp.init()` — and its
//  `MusicShareKit.configure(...)` call — has already executed in this same
//  process. That IS a runtime seam, contrary to what an earlier version of
//  this comment claimed, and asserting
//  `MusicShareKit.configuration.featureFlagProvider != nil` directly is
//  stronger than any text scan and immune to reformatting. The Share
//  Extension is a separate process this test target never launches, so its
//  call site (`ShareViewController.swift`) has no such seam and stays
//  source-scanned, for the same reason `LaunchSequenceOrderingTests` reads
//  `WXYCApp.swift` as text: there is no other observable signal short of a
//  PostHog absence. That scan reuses `SourceScan.boundedLines`, the helper
//  factored out of `LaunchSequenceOrderingTests` — including its
//  block-comment refusal guard, which an earlier version of this file's own
//  copy of the scan had dropped.
//
//  Created by Jake Bromberg on 08/27/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import MusicShareKit
import Testing

@Suite("Feature flag provider wiring")
struct FeatureFlagProviderWiringTests {

    private static func iosDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WXYCTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // iOS
    }

    @Test("WXYCApp has configured MusicShareKit with a non-nil featureFlagProvider")
    func wxycAppConfiguresNonNilProvider() {
        // WXYCTests is a hosted test target (TEST_HOST = WXYC.app), so
        // WXYCApp.init() has already run in this process by the time this
        // test executes — reading the live configuration is a direct
        // behavioural check, not a proxy for one.
        #expect(MusicShareKit.configuration.featureFlagProvider != nil)
    }

    @Test("ShareViewController.swift passes a non-nil featureFlagProvider to MusicShareKit.configure(...)")
    func shareViewControllerPassesNonNilProvider() throws {
        let url = Self.iosDirectory()
            .appendingPathComponent("Request Share Extension")
            .appendingPathComponent("ShareViewController.swift")

        let callLines = try SourceScan.boundedLines(
            of: url,
            start: { $0.hasPrefix("MusicShareKit.configure(MusicShareKitConfiguration(") },
            startNotFoundMessage: """
            ShareViewController.swift no longer calls \
            MusicShareKit.configure(MusicShareKitConfiguration(...)) — update \
            this test's scan target rather than deleting the check.
            """,
            open: "(",
            close: ")"
        )

        let providerLine = try #require(
            callLines.first { $0.hasPrefix("featureFlagProvider:") },
            """
            ShareViewController.swift's MusicShareKit.configure(...) call no \
            longer passes featureFlagProvider — update this test's scan \
            target rather than deleting the check.
            """
        )

        #expect(
            !providerLine.hasPrefix("featureFlagProvider: nil"),
            """
            ShareViewController.swift passes featureFlagProvider: nil to \
            MusicShareKit.configure(...).

            RequestLineAuthFeature.isEnabled(...) takes its step-3 branch on \
            every call when no provider is wired, which disables \
            request-line authentication for the whole process. See \
            WXYC/wxyc-ios-64#385 and WXYC/wxyc-ios-64#1012 — the previous \
            regression here went unshipped on master for nearly three months \
            because nothing caught it.
            """
        )
    }
}
