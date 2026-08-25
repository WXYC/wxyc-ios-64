//
//  LaunchSequenceOrderingTests.swift
//  WXYC
//
//  Pins the one ordering constraint in `WXYCApp.init()` that fails silently:
//  analytics must be started before anything captures an event or configures
//  a subsystem that captures on its way up, because PostHog drops pre-`setup`
//  captures rather than buffering them (WXYC/wxyc-ios-64#1002).
//
//  Source-scanning rather than behavioural, for the same reason the defect
//  survived undetected: the failure has no runtime signal. `PostHogSDK`
//  swallows the call, `capture` returns void, and the only evidence is an
//  event that never arrives in a project nobody was watching. There is no
//  seam to assert against — `AnalyticsBootstrap.start` writes to a private
//  flag inside a vendored singleton — so the invariant is checked where it is
//  actually expressed: the order of statements in one initializer. The
//  precedent for reading source in a test is `AppIntentsDependenciesTests`,
//  including its guard against passing vacuously when the file cannot be read.
//
//  KNOWN BLIND SPOT — read before trusting a green run. This scans the body of
//  `init()`. Swift evaluates stored-property default expressions BEFORE the
//  first statement of that body, so `@State private var appState =
//  Singletonia.shared` and any feature-flag or capture call reachable from it
//  are outside what this test can see, and outside what moving a statement
//  inside `init()` can fix. That gap is real and tracked separately; it is not
//  something to "fix" by loosening this test.
//
//  Created by Jake Bromberg on 08/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing

@Suite("Launch sequence ordering")
struct LaunchSequenceOrderingTests {

    /// Calls that either capture an event directly or configure a subsystem
    /// that captures during its own initialization. Every one of these must
    /// sit below `setUpAnalytics()`.
    private static let capturingCalls = [
        "MusicShareKit.configure(",
        "StructuredPostHogAnalytics.shared.capture(",
    ]

    private static let analyticsCall = "AppBootstrap.setUpAnalytics()"

    /// The trimmed code lines of `WXYCApp.init()`'s body, located relative to
    /// this file so the test moves with the target rather than depending on a
    /// bundle resource.
    ///
    /// Line comments are dropped before matching. Both call sites are
    /// documented with comments that name the very calls this test searches
    /// for, so a naive scan finds the prose above the code and reports the
    /// opposite of the truth — this test failed against the fixed file until
    /// it learned to skip comments.
    private static func initBodyLines() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // WXYCTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // iOS
            .appendingPathComponent("WXYCApp.swift")
        let all = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let start = try #require(
            all.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "init() {" },
            "Couldn't find `init() {` in WXYCApp.swift — the scan below would pass vacuously."
        )

        // Brace-count to the matching close so a `.capture(` in some later
        // method can't be mistaken for one on the launch path.
        var depth = 0
        var end = all.count
        for index in start..<all.count {
            let line = all[index].trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("//") else { continue }
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0 {
                end = index
                break
            }
        }

        let body = all[start...min(end, all.count - 1)]
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // This test reasons about `//` only. A block comment inside `init()`
        // could hide a call from the scan, or contribute a line that looks
        // like one — either way the result stops meaning anything, so refuse
        // rather than report a number that isn't true.
        #expect(
            !body.contains { $0.contains("/*") },
            "WXYCApp.init() now contains a block comment. This test only strips `//` lines, so its result is no longer trustworthy — teach it to skip block comments before relying on it again."
        )

        return body.filter { !$0.hasPrefix("//") }
    }

    @Test("Analytics is started before anything on the launch path captures")
    func analyticsStartsBeforeAnythingCaptures() throws {
        let body = try Self.initBodyLines()

        // `hasPrefix`, not `contains`: a statement begins with its call, while
        // a comment or doc line mentioning it does not. Combined with the
        // block-comment refusal above, that keeps prose from moving the result.
        let analytics = try #require(
            body.firstIndex { $0.hasPrefix(Self.analyticsCall) },
            "\(Self.analyticsCall) is no longer called from WXYCApp.init(). If the launch sequence moved, move this test with it rather than deleting it — see WXYC/wxyc-ios-64#1002."
        )

        // Assert the invariant, not the one pair that happened to break it.
        // The original defect was `MusicShareKit.configure(` above analytics;
        // the same bug returns unnoticed if a NEW capturing call is added
        // above it, which a hardcoded two-call comparison would not catch.
        for call in Self.capturingCalls {
            guard let offender = body.firstIndex(where: { $0.hasPrefix(call) }) else { continue }
            #expect(
                analytics < offender,
                """
                `\(call)` runs before `\(Self.analyticsCall)` in WXYCApp.init().

                PostHogSDK.capture gates on a private isEnabled() that only \
                becomes true inside AnalyticsBootstrap.start -> \
                PostHogSDK.shared.setup, and it DISCARDS calls made before \
                then — it does not queue them. Anything captured above that \
                line is silently dropped on every launch, and a zero reading \
                for the event becomes evidence of nothing. That is exactly how \
                WXYC/wxyc-ios-64#996 came to rule out a live hypothesis.

                Do not fix this by buffering pre-setup events. Start analytics \
                first.
                """
            )
        }

        // At least one capturing call must be present, or the loop above is a
        // no-op and this test passes without checking anything.
        #expect(
            Self.capturingCalls.contains { call in body.contains { $0.hasPrefix(call) } },
            "None of \(Self.capturingCalls) appear in WXYCApp.init() any more. Update this list — as written the ordering check just passed vacuously."
        )
    }
}
