//
//  FeatureFlagProviderWiringTests.swift
//  WXYC
//
//  Pins that both production `MusicShareKit.configure(...)` call sites pass a
//  non-nil `featureFlagProvider` (#1012). A missing provider makes
//  `MusicShareKit.isAuthEnabled()` take its guard branch on every call, which
//  now captures `source: .unwired` rather than returning `false` silently —
//  but the right fix is to keep the provider wired in the first place, and
//  this is the direct test for that: WXYC/wxyc-ios-64#385 wired it in
//  `caf413388` and then sat unshipped on master for nearly three months with
//  nothing catching a regression.
//
//  Source-scanning rather than behavioural, for the same reason
//  `LaunchSequenceOrderingTests` reads `WXYCApp.swift` as text: there is no
//  runtime seam for "was `configure(...)` called with a nil provider" once
//  the process has actually launched with one, and the failure mode this
//  guards has no other observable signal short of a PostHog absence.
//
//  Created by Jake Bromberg on 08/27/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing

/// (label, path relative to the `iOS` directory, split into components so a
/// space in "Request Share Extension" doesn't need escaping).
///
/// Top-level and `nonisolated` rather than a static member of the suite:
/// `@Test(arguments:)` evaluates its argument list outside the suite
/// instance, and this module defaults to `MainActor` isolation
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION`), so an implicitly-isolated file-scope
/// `let` fails to compile there — see `ThemeCyclingTests.cyclingSteps` for
/// the same fix applied to the same failure mode.
private nonisolated let productionCallSites: [(label: String, relativePath: [String])] = [
    ("WXYCApp.swift", ["WXYCApp.swift"]),
    ("ShareViewController.swift", ["Request Share Extension", "ShareViewController.swift"]),
]

@Suite("Feature flag provider wiring")
struct FeatureFlagProviderWiringTests {

    private static func iosDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WXYCTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // iOS
    }

    @Test(
        "MusicShareKit.configure(...) passes a non-nil featureFlagProvider",
        arguments: productionCallSites
    )
    func configureCallSitePassesNonNilProvider(_ site: (label: String, relativePath: [String])) throws {
        var url = Self.iosDirectory()
        for component in site.relativePath {
            url.appendPathComponent(component)
        }

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let configureIndex = try #require(
            lines.firstIndex { $0.hasPrefix("MusicShareKit.configure(MusicShareKitConfiguration(") },
            """
            \(site.label) no longer calls MusicShareKit.configure(MusicShareKitConfiguration(...)) — \
            update this test's scan target rather than deleting the check.
            """
        )

        // Brace-count from the configure( call to its matching close so a
        // featureFlagProvider mentioned in a later, unrelated call can't be
        // mistaken for this one's argument.
        var depth = 0
        var end = lines.count
        for index in configureIndex..<lines.count {
            let line = lines[index]
            guard !line.hasPrefix("//") else { continue }
            depth += line.filter { $0 == "(" }.count
            depth -= line.filter { $0 == ")" }.count
            if depth == 0 {
                end = index
                break
            }
        }

        let callLines = lines[configureIndex...min(end, lines.count - 1)]

        let providerLine = try #require(
            callLines.first { $0.hasPrefix("featureFlagProvider:") },
            """
            \(site.label)'s MusicShareKit.configure(...) call no longer passes featureFlagProvider — \
            update this test's scan target rather than deleting the check.
            """
        )

        #expect(
            !providerLine.hasPrefix("featureFlagProvider: nil"),
            """
            \(site.label) passes featureFlagProvider: nil to MusicShareKit.configure(...).

            MusicShareKit.isAuthEnabled() takes its guard branch on every call \
            when no provider is wired, which disables request-line \
            authentication for the whole process. See WXYC/wxyc-ios-64#385 and \
            WXYC/wxyc-ios-64#1012 — the previous regression here went \
            unshipped on master for nearly three months because nothing \
            caught it.
            """
        )
    }
}
