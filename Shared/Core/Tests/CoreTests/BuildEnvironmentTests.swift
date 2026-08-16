//
//  BuildEnvironmentTests.swift
//  Core
//
//  Pins the classification Sentry's `environment` option is set from: the full
//  truth table over (debug build, simulator, sandbox receipt), the precedence
//  that keeps a simulator run out of `production` however it was configured,
//  and the raw strings the Sentry dashboard filters on.
//
//  Created by Jake Bromberg on 08/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Core

@Suite("Build environment")
struct BuildEnvironmentTests {

    @Test(
        "Every permutation of the three build facts classifies as expected",
        arguments: buildEnvironmentTruthTable
    )
    func classifiesEveryPermutation(
        isDebugBuild: Bool,
        isSimulator: Bool,
        hasSandboxReceipt: Bool,
        expected: BuildEnvironment
    ) {
        let environment = BuildEnvironment(
            isDebugBuild: isDebugBuild,
            isSimulator: isSimulator,
            hasSandboxReceipt: hasSandboxReceipt
        )

        #expect(environment == expected)
    }

    /// The bug itself, stated as an invariant rather than as a row: before this
    /// type existed the SDK defaulted every build to `production`, so six of the
    /// eight permutations below were filing developer traffic under real user
    /// traffic. Asserting the subset size first keeps this from passing
    /// vacuously if a future edit thins the table out.
    @Test("No build a developer is running ever classifies as production")
    func developerBuildsAreNeverProduction() {
        let developerCases = buildEnvironmentTruthTable.filter { $0.isDebugBuild || $0.isSimulator }

        #expect(
            developerCases.count == 6,
            "Truth table lost developer permutations, so the loop below proves nothing"
        )

        for testCase in developerCases {
            let environment = BuildEnvironment(
                isDebugBuild: testCase.isDebugBuild,
                isSimulator: testCase.isSimulator,
                hasSandboxReceipt: testCase.hasSandboxReceipt
            )

            #expect(
                environment != .production,
                """
                debug=\(testCase.isDebugBuild) simulator=\(testCase.isSimulator) \
                sandboxReceipt=\(testCase.hasSandboxReceipt) classified as production
                """
            )
        }
    }

    /// `Debug TestFlight` — what the WXYC scheme's Test action builds — carries
    /// the *release* bundle id `org.wxyc.iphoneapp`, so a simulator run is
    /// indistinguishable from a shipped build by bundle id alone (Sentry IOS-41).
    /// The simulator arm has to win over everything downstream of it for that
    /// traffic to land anywhere other than `production`.
    @Test("A simulator run classifies as simulator whatever else is true of it")
    func simulatorOutranksTheRemainingFacts() {
        for isDebugBuild in [true, false] {
            for hasSandboxReceipt in [true, false] {
                let environment = BuildEnvironment(
                    isDebugBuild: isDebugBuild,
                    isSimulator: true,
                    hasSandboxReceipt: hasSandboxReceipt
                )

                #expect(environment == .simulator)
            }
        }
    }

    @Test(
        "A sandbox receipt is recognised by file name, not by path",
        arguments: [
            // No receipt on disk at all — Xcode-installed builds routinely have
            // none. Absence is not evidence of TestFlight.
            (URL?.none, false),
            (URL(filePath: "/var/mobile/.../StoreKit/sandboxReceipt"), true),
            // What an App Store install writes instead.
            (URL(filePath: "/var/mobile/.../StoreKit/receipt"), false),
            // Only the last component counts; a directory of that name is not a
            // receipt.
            (URL(filePath: "/var/mobile/sandboxReceipt/receipt"), false),
        ]
    )
    func recognisesTheSandboxReceipt(receiptURL: URL?, expected: Bool) {
        #expect(BuildEnvironment.hasSandboxReceipt(at: receiptURL) == expected)
    }

    /// Sentry filters, saved searches and alert rules key off these exact
    /// strings, so a case rename is a dashboard migration rather than a
    /// refactor. Pinned here so it cannot happen silently.
    @Test(
        "Raw values are the strings Sentry stores",
        arguments: [
            (BuildEnvironment.simulator, "simulator"),
            (BuildEnvironment.debug, "debug"),
            (BuildEnvironment.testflight, "testflight"),
            (BuildEnvironment.production, "production"),
        ]
    )
    func rawValuesAreStable(environment: BuildEnvironment, expected: String) {
        #expect(environment.rawValue == expected)
    }

    /// The one assertion that exercises `current`'s `#if` wiring, which is
    /// otherwise unreachable from a test — a compile-time fact cannot be varied
    /// at runtime. It is not a tautology on either path this suite runs on:
    /// `swift test` on the host builds Debug on non-simulator hardware and must
    /// reach `.debug`, while the same target under `WXYC.xctestplan` builds
    /// `Debug TestFlight` in the simulator and must reach `.simulator`. Deleting
    /// either arm of the cascade drops one of those runs into `.production` and
    /// reddens this.
    @Test("The process running these tests is never classified as production")
    func theTestProcessIsNeverProduction() {
        #expect(BuildEnvironment.current != .production)
    }
}

// MARK: - Fixtures

/// Every combination of the three facts `BuildEnvironment` is derived from.
///
/// At file scope, and explicitly typed, because a tuple array this wide inline
/// in `arguments:` is slow enough to type-check to be worth avoiding; and
/// `nonisolated` so it stays readable from `arguments:`, which is evaluated
/// outside any actor.
nonisolated let buildEnvironmentTruthTable: [
    (isDebugBuild: Bool, isSimulator: Bool, hasSandboxReceipt: Bool, expected: BuildEnvironment)
] = [
    // Simulator, whatever the configuration. `BGTaskScheduler` and friends are
    // genuinely absent here, which is why this traffic has to be separable —
    // Sentry IOS-1S/IOS-20/IOS-1V are all this case.
    (true, true, true, .simulator),
    (true, true, false, .simulator),
    (false, true, true, .simulator),
    (false, true, false, .simulator),

    // Debug configuration on real hardware: an Xcode run on the developer's own
    // device. Both `Debug` and `Debug TestFlight` land here, and the latter's
    // receipt state is not something the developer controls.
    (true, false, true, .debug),
    (true, false, false, .debug),

    // Release archive on real hardware. The receipt is the only thing that
    // separates these two — the scheme archives both from `Release`, so no
    // compile-time fact can.
    (false, false, true, .testflight),
    (false, false, false, .production),
]
