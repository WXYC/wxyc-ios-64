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
        "Every permutation of the four build facts classifies as expected",
        arguments: buildEnvironmentTruthTable
    )
    func classifiesEveryPermutation(
        isDebugBuild: Bool,
        isSimulator: Bool,
        hasSandboxReceipt: Bool,
        hasProvisioningProfile: Bool,
        expected: BuildEnvironment
    ) {
        let environment = BuildEnvironment(
            isDebugBuild: isDebugBuild,
            isSimulator: isSimulator,
            hasSandboxReceipt: hasSandboxReceipt,
            hasProvisioningProfile: hasProvisioningProfile
        )

        #expect(environment == expected)
    }

    /// The bug itself, stated as an invariant rather than as a row: before this
    /// type existed the SDK defaulted every build to `production`, so most of
    /// the permutations below were filing developer traffic under real user
    /// traffic. Asserting the subset size first keeps this from passing
    /// vacuously if a future edit thins the table out.
    @Test("No build a developer is running ever classifies as production")
    func developerBuildsAreNeverProduction() {
        let developerCases = buildEnvironmentTruthTable.filter {
            $0.isDebugBuild || $0.isSimulator || $0.hasProvisioningProfile
        }

        #expect(
            developerCases.count == 14,
            "Truth table lost developer permutations, so the loop below proves nothing"
        )

        for testCase in developerCases {
            let environment = BuildEnvironment(
                isDebugBuild: testCase.isDebugBuild,
                isSimulator: testCase.isSimulator,
                hasSandboxReceipt: testCase.hasSandboxReceipt,
                hasProvisioningProfile: testCase.hasProvisioningProfile
            )

            #expect(
                environment != .production,
                """
                debug=\(testCase.isDebugBuild) simulator=\(testCase.isSimulator) \
                sandboxReceipt=\(testCase.hasSandboxReceipt) \
                provisioningProfile=\(testCase.hasProvisioningProfile) classified as production
                """
            )
        }
    }

    /// The regression that motivated the fourth fact. The WXYC scheme's Profile
    /// action builds `Release`, and an Xcode-installed Release build has no App
    /// Store receipt — so on the first three facts alone it was indistinguishable
    /// from a real user, and profiling a device to chase a hang filed as
    /// production traffic. Ad-hoc and enterprise installs land here too; all
    /// three carry `embedded.mobileprovision`, which a store build never does.
    @Test("A Release build profiled on a real device is not production")
    func profiledReleaseBuildIsNotProduction() {
        let environment = BuildEnvironment(
            isDebugBuild: false,
            isSimulator: false,
            hasSandboxReceipt: false,
            hasProvisioningProfile: true
        )

        #expect(environment == .adhoc)
    }

    /// Order matters between the last two facts, and only one direction is safe.
    /// A sandbox receipt is positive evidence of TestFlight; the absence of a
    /// provisioning profile is only indirect evidence about it, and whether
    /// TestFlight strips `embedded.mobileprovision` is not something this code
    /// should depend on. Checking the receipt first keeps TestFlight classified
    /// correctly either way.
    @Test("A sandbox receipt wins over a provisioning profile")
    func sandboxReceiptOutranksProvisioningProfile() {
        let environment = BuildEnvironment(
            isDebugBuild: false,
            isSimulator: false,
            hasSandboxReceipt: true,
            hasProvisioningProfile: true
        )

        #expect(environment == .testflight)
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
                for hasProvisioningProfile in [true, false] {
                    let environment = BuildEnvironment(
                        isDebugBuild: isDebugBuild,
                        isSimulator: true,
                        hasSandboxReceipt: hasSandboxReceipt,
                        hasProvisioningProfile: hasProvisioningProfile
                    )

                    #expect(environment == .simulator)
                }
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
            (BuildEnvironment.adhoc, "adhoc"),
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
    ///
    /// Gated because outside those two builds the assertion is not about this
    /// code at all. Under `swift test -c release` on the macOS host every fact
    /// is false — no `DEBUG`, no simulator, no App Store receipt, no
    /// provisioning profile — so `.production` is the *correct* answer and the
    /// test would fail for the environment rather than for a regression. The
    /// gate states the precondition instead of asserting through it.
    #if DEBUG || targetEnvironment(simulator)
    @Test("The process running these tests is never classified as production")
    func theTestProcessIsNeverProduction() {
        #expect(BuildEnvironment.current != .production)
    }
    #endif
}

// MARK: - Fixtures

/// Every combination of the four facts `BuildEnvironment` is derived from.
///
/// At file scope, and explicitly typed, because a tuple array this wide inline
/// in `arguments:` is slow enough to type-check to be worth avoiding; and
/// `nonisolated` so it stays readable from `arguments:`, which is evaluated
/// outside any actor.
nonisolated let buildEnvironmentTruthTable: [
    (
        isDebugBuild: Bool,
        isSimulator: Bool,
        hasSandboxReceipt: Bool,
        hasProvisioningProfile: Bool,
        expected: BuildEnvironment
    )
] = [
    // Simulator, whatever the configuration. `BGTaskScheduler` and friends are
    // genuinely absent here, which is why this traffic has to be separable —
    // Sentry IOS-1S/IOS-20/IOS-1V are all this case.
    (true, true, true, true, .simulator),
    (true, true, true, false, .simulator),
    (true, true, false, true, .simulator),
    (true, true, false, false, .simulator),
    (false, true, true, true, .simulator),
    (false, true, true, false, .simulator),
    (false, true, false, true, .simulator),
    (false, true, false, false, .simulator),

    // Debug configuration on real hardware: an Xcode run on the developer's own
    // device. Both `Debug` and `Debug TestFlight` land here, and neither the
    // receipt nor the profile is something the developer controls.
    (true, false, true, true, .debug),
    (true, false, true, false, .debug),
    (true, false, false, true, .debug),
    (true, false, false, false, .debug),

    // Release build on real hardware, holding a sandbox receipt: TestFlight.
    // The scheme archives TestFlight and App Store from the one `Release`
    // configuration, so no compile-time fact separates them.
    (false, false, true, true, .testflight),
    (false, false, true, false, .testflight),

    // Release build a developer put on a device themselves — the Profile
    // action, an ad-hoc build, an enterprise install. Optimised like a shipped
    // build, so not `debug`, but not a real user either.
    (false, false, false, true, .adhoc),

    // The only row that is a real user.
    (false, false, false, false, .production),
]
