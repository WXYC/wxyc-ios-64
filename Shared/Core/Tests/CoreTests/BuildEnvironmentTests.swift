//
//  BuildEnvironmentTests.swift
//  Core
//
//  Pins the classification Sentry's `environment` option is set from: the full
//  truth table over the four build facts (debug build, simulator, sandbox
//  receipt, provisioning profile), the two bundle layouts a provisioning
//  profile can sit in, and the raw strings the Sentry dashboard filters on.
//
//  Created by Jake Bromberg on 08/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Core

@Suite("Build environment")
struct BuildEnvironmentTests {

    // MARK: - Classification

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

    /// The guard that makes the row-by-row assertions above worth anything.
    /// They only cover what the table lists, so a thinned table would narrow the
    /// coverage silently. Asserting *distinct* fact combinations rather than a
    /// bare row count means duplicated rows cannot pad it back to 16 either.
    @Test("The truth table covers every permutation exactly once")
    func truthTableIsExhaustive() {
        let combinations = Set(
            buildEnvironmentTruthTable.map {
                [$0.isDebugBuild, $0.isSimulator, $0.hasSandboxReceipt, $0.hasProvisioningProfile]
            }
        )

        #expect(buildEnvironmentTruthTable.count == 16)
        #expect(combinations.count == 16)
    }

    // MARK: - The facts themselves

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

    /// The two layouts a provisioning profile can sit in, both exercised on this
    /// platform. The Catalyst case is the one that was wrong: a Catalyst app is
    /// a macOS-style bundle, so its profile is `Contents/embedded.provisionprofile`
    /// rather than `embedded.mobileprovision` at the root, and a build outside
    /// the store was falling through to `production` — the exact bug `adhoc`
    /// exists to prevent, on a destination `SUPPORTS_MACCATALYST = YES` supports.
    @Test(
        "A profile is found at either bundle layout",
        arguments: [
            ("embedded.mobileprovision", "embedded.mobileprovision", true),
            ("Contents/embedded.provisionprofile", "Contents/embedded.provisionprofile", true),
            // The layouts are genuinely distinct: looking for the iOS path in a
            // Catalyst-shaped bundle finds nothing. This is what the old
            // implementation was doing on Catalyst.
            ("Contents/embedded.provisionprofile", "embedded.mobileprovision", false),
            ("embedded.mobileprovision", "Contents/embedded.provisionprofile", false),
        ]
    )
    func findsAProfileAtEitherLayout(
        profileOnDisk: String,
        lookingFor: String,
        expected: Bool
    ) throws {
        let bundleURL = try makeBundleDirectory(containing: profileOnDisk)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        #expect(
            BuildEnvironment.containsProvisioningProfile(at: bundleURL, relativePath: lookingFor) == expected
        )
    }

    @Test("A bundle with no profile at all reports none")
    func bundleWithoutAProfileReportsNone() throws {
        let bundleURL = try makeBundleDirectory(containing: nil)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        #expect(
            BuildEnvironment.containsProvisioningProfile(
                at: bundleURL,
                relativePath: BuildEnvironment.provisioningProfileBundlePath
            ) == false
        )
    }

    /// Covers the `Bundle`-taking seam against a real bundle. The test runner is
    /// never signed with a provisioning profile, on either the host or the
    /// simulator, so `false` is the honest answer rather than a stubbed one —
    /// and it fails loudly if the lookup ever starts matching a directory or
    /// throwing.
    @Test("The bundle under test carries no provisioning profile")
    func mainBundleUnderTestHasNoProfile() {
        #expect(BuildEnvironment.hasProvisioningProfile(in: .main) == false)
    }

    /// The platform constant cannot be varied at runtime, so this is the only
    /// thing worth asserting about it: on every platform this suite runs on —
    /// the macOS host and the iOS simulator, neither of which is Catalyst — it
    /// must be the iOS name. Inverting the `#if` reddens this. The Catalyst
    /// branch's *value* is unreachable from here; its *behaviour* is covered by
    /// the layout test above, which exercises the Catalyst path explicitly.
    #if !targetEnvironment(macCatalyst)
    @Test("The profile path is the iOS one off Catalyst")
    func profilePathMatchesThePlatform() {
        #expect(BuildEnvironment.provisioningProfileBundlePath == "embedded.mobileprovision")
    }
    #endif

    // MARK: - Wire contract

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

/// Creates a throwaway directory shaped like an app bundle, optionally holding a
/// file at `relativePath`. Real directories rather than a `Bundle` double
/// because the thing under test is a path layout on disk.
private func makeBundleDirectory(containing relativePath: String?) throws -> URL {
    let root = URL.temporaryDirectory.appending(path: "BuildEnvironmentTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    if let relativePath {
        let profile = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: profile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: profile)
    }

    return root
}

/// Every combination of the four facts `BuildEnvironment` is derived from, with
/// the precedence reasoning on the rows it applies to.
///
/// `private` because a file-scope global in a multi-file test module is a name
/// collision waiting to happen; `@Test(arguments:)` still reaches it, being
/// evaluated in this file. At file scope and explicitly typed because a tuple
/// array this wide inline in `arguments:` is slow to type-check, and
/// `nonisolated` so it stays readable from `arguments:`, which is evaluated
/// outside any actor.
private nonisolated let buildEnvironmentTruthTable: [
    (
        isDebugBuild: Bool,
        isSimulator: Bool,
        hasSandboxReceipt: Bool,
        hasProvisioningProfile: Bool,
        expected: BuildEnvironment
    )
] = [
    // The simulator wins over every other fact, which is why all eight of its
    // rows are here rather than a representative few. It is a property of where
    // the build is *running* and survives any configuration choice, and nothing
    // else on the event identifies it: the scheme's Test action builds
    // `Debug TestFlight`, which carries the *release* bundle id
    // `org.wxyc.iphoneapp`, so a simulator run looks shipped by bundle id alone
    // (Sentry IOS-41). `BGTaskScheduler` and friends are genuinely absent here,
    // which is why the traffic has to be separable at all.
    (true, true, true, true, .simulator),
    (true, true, true, false, .simulator),
    (true, true, false, true, .simulator),
    (true, true, false, false, .simulator),
    (false, true, true, true, .simulator),
    (false, true, true, false, .simulator),
    (false, true, false, true, .simulator),
    (false, true, false, false, .simulator),

    // Debug configuration on real hardware: an Xcode run on the developer's own
    // device. Both `Debug` and `Debug TestFlight` define `DEBUG` and land here,
    // and neither the receipt nor the profile is something the developer
    // controls, so all four combinations of them stay `debug`.
    (true, false, true, true, .debug),
    (true, false, true, false, .debug),
    (true, false, false, true, .debug),
    (true, false, false, false, .debug),

    // Release build on real hardware holding a sandbox receipt: TestFlight. The
    // scheme archives TestFlight and App Store from the one `Release`
    // configuration, so no compile-time fact separates them and the receipt has
    // to. It is checked *before* the profile deliberately: a sandbox receipt is
    // positive evidence of TestFlight, whereas a missing profile is only
    // indirect evidence about it, and whether TestFlight strips the profile is
    // not something this code should have to be right about. Receipt-first
    // classifies TestFlight correctly either way — hence both rows below.
    (false, false, true, true, .testflight),
    (false, false, true, false, .testflight),

    // Release build a developer put on a device themselves — the Profile action,
    // an ad-hoc build, an enterprise install. Optimised like a shipped build, so
    // not `debug`, but not a real user either: profiling a device to chase a
    // hang used to file as production traffic, which is what this row prevents.
    (false, false, false, true, .adhoc),

    // The only row that is a real user.
    (false, false, false, false, .production),
]
