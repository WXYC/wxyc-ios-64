//
//  BuildEnvironment.swift
//  Core
//
//  Answers one question about the running build: is this developer traffic or a
//  real user? Telemetry back ends want it as a single low-cardinality string —
//  Sentry's `environment` option is the consumer today. Lives in Core, next to
//  `ForegroundVisibility`, because it is the same shape of thing: a pure
//  classification of an ambient fact, needed by any layer that reports
//  telemetry and dependent on nothing but Foundation.
//
//  Created by Jake Bromberg on 08/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Which kind of build is running, as a telemetry back end wants to slice it.
///
/// Sentry defaults `environment` to `production` when it is not set, so leaving
/// it unset filed every simulator run, Xcode run and TestFlight session under
/// real user traffic — whole issues that read as production incidents were the
/// developer's own machine (`BGTaskScheduler is not available on this platform`,
/// Sentry IOS-1S/IOS-20/IOS-1V; the v2 playlist timeouts, IOS-2S/1T/24/3Y).
///
/// Four cases, because four is what the build matrix can actually distinguish
/// and each one changes how an issue should be triaged:
///
/// - ``simulator`` and ``debug`` are both the developer, split apart because
///   they differ in which system APIs exist at all. The `BGTaskScheduler` issues
///   above are simulator-only in a way no device build can reproduce, so folding
///   them together would keep a whole class of non-bug noise in with real ones.
/// - ``testflight`` is a beta tester on real hardware: a genuine report, but one
///   whose fix does not need a submission to reach the reporter.
/// - ``production`` is what the name has always claimed and now finally means.
///
/// Deliberately *not* split further by platform. Mac Catalyst is a supported
/// destination (`SUPPORTS_MACCATALYST = YES`) and classifies correctly through
/// the same three facts, and Sentry already tags `os.name` and `device.family`,
/// so a `catalyst` case would multiply every row above without answering a
/// question the existing tags do not. tvOS and watchOS never reach this type at
/// all — the iOS app target holds the only `SentrySDK.start` call site.
public enum BuildEnvironment: String, Sendable {
    /// Running in the iOS Simulator, in any configuration.
    case simulator
    /// A debug-configured build on real hardware: an Xcode run.
    case debug
    /// A release archive installed through TestFlight.
    case testflight
    /// A release archive installed from the App Store. Real users, at last.
    case production
}

public extension BuildEnvironment {
    /// Classifies a build from the three facts that separate the cases.
    ///
    /// Order is the substance of this initializer, so each arm is worth stating:
    ///
    /// 1. The simulator wins outright. It is a property of where the build is
    ///    *running*, and it survives any configuration choice — where the other
    ///    two facts describe how the binary was built. Ignoring that ordering is
    ///    how simulator crashes reached `production` in the first place: the
    ///    WXYC scheme's Test action builds `Debug TestFlight`, whose bundle id is
    ///    the release one, `org.wxyc.iphoneapp`, so neither the bundle id nor
    ///    the configuration name identifies a simulator run (Sentry IOS-41).
    /// 2. A debug build that got past the first arm is on real hardware, which
    ///    means someone ran it from Xcode. Both `Debug` and `Debug TestFlight`
    ///    define `DEBUG` and both land here.
    /// 3. What remains is a release archive, and the receipt is the only thing
    ///    that separates a beta tester from a real one. It has to be: the scheme
    ///    archives TestFlight and App Store builds from the same `Release`
    ///    configuration, so no compile-time fact tells them apart.
    ///
    /// - Parameters:
    ///   - isDebugBuild: Whether `DEBUG` was defined when this was compiled.
    ///   - isSimulator: Whether the build targets the simulator.
    ///   - hasSandboxReceipt: Whether the App Store receipt is the sandbox one.
    init(isDebugBuild: Bool, isSimulator: Bool, hasSandboxReceipt: Bool) {
        if isSimulator {
            self = .simulator
        } else if isDebugBuild {
            self = .debug
        } else if hasSandboxReceipt {
            self = .testflight
        } else {
            self = .production
        }
    }

    /// The environment this process is actually running in.
    ///
    /// The only part of this type that cannot be unit-tested, and kept to the
    /// smallest shape that can be: it does nothing but read the two
    /// compile-time facts and the receipt, then hand all three to the
    /// initializer above. A compile-time directive cannot be varied at runtime,
    /// so the coverage that matters lives on ``init(isDebugBuild:isSimulator:hasSandboxReceipt:)``
    /// and ``hasSandboxReceipt(at:)`` instead — the same split
    /// `AnalyticsBootstrap.watchOSOSSuperProperties(systemVersion:)` uses to
    /// keep its own platform gate out of the testable part.
    static var current: BuildEnvironment {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif

        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif

        return BuildEnvironment(
            isDebugBuild: isDebugBuild,
            isSimulator: isSimulator,
            hasSandboxReceipt: hasSandboxReceipt(at: Bundle.main.appStoreReceiptURL)
        )
    }
}

extension BuildEnvironment {
    /// Whether a receipt URL points at the sandbox receipt TestFlight installs
    /// write, rather than the App Store's.
    ///
    /// Matched on the file name alone: the containing directory differs between
    /// OS versions and between iOS and Mac Catalyst, while the name does not.
    /// A missing URL is not evidence of anything — Xcode-installed builds
    /// routinely have no receipt on disk — and reads as "not TestFlight", which
    /// is safe here because the debug arm has already claimed those builds.
    ///
    /// - Parameter receiptURL: `Bundle.main.appStoreReceiptURL`, or `nil`.
    /// - Returns: `true` for a sandbox receipt.
    static func hasSandboxReceipt(at receiptURL: URL?) -> Bool {
        receiptURL?.lastPathComponent == sandboxReceiptName
    }

    private static let sandboxReceiptName = "sandboxReceipt"
}
