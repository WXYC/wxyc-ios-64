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
/// Five cases, because five is what the build matrix can actually distinguish
/// and each one changes how an issue should be triaged:
///
/// - ``simulator`` and ``debug`` are both the developer, split apart because
///   they differ in which system APIs exist at all. The `BGTaskScheduler` issues
///   above are simulator-only in a way no device build can reproduce, so folding
///   them together would keep a whole class of non-bug noise in with real ones.
/// - ``adhoc`` is a release-optimised build a developer put on a device
///   themselves. Still not a real user, but it does not behave like ``debug``:
///   it is built `-O`, which is exactly why the Profile action exists.
/// - ``testflight`` is a beta tester on real hardware: a genuine report, but one
///   whose fix does not need a submission to reach the reporter.
/// - ``production`` is what the name has always claimed and now finally means.
///
/// Deliberately *not* split further by platform. Mac Catalyst is a supported
/// destination (`SUPPORTS_MACCATALYST = YES`) and classifies through the same
/// four facts — see ``provisioningProfileBundlePath`` for the one place the
/// platform genuinely differs — while Sentry already tags `os.name` and
/// `device.family`, so a `catalyst` case would multiply every row above without
/// answering a question the existing tags do not. tvOS and watchOS never reach
/// this type at all: the iOS app target holds the only `SentrySDK.start` call.
public enum BuildEnvironment: String, Sendable {
    /// Running in the iOS Simulator, in any configuration.
    case simulator
    /// A debug-configured build on real hardware: an Xcode run.
    case debug
    /// A release-configured build installed outside the store — the Profile
    /// action, an ad-hoc build, an enterprise install.
    case adhoc
    /// A release archive installed through TestFlight.
    case testflight
    /// A release archive installed from the App Store. Real users, at last.
    case production
}

public extension BuildEnvironment {
    /// The environment this process is actually running in.
    ///
    /// Computed once: every fact behind it is fixed for the lifetime of the
    /// process, and the file checks below are not worth repeating.
    ///
    /// This is the only part of the type that cannot be unit-tested, and it is
    /// kept to the smallest shape that can be: it reads the two compile-time
    /// facts, the receipt and the profile, and hands all four to the
    /// initializer. A compile-time directive cannot be varied at runtime, so the
    /// coverage that matters lives on
    /// ``init(isDebugBuild:isSimulator:hasSandboxReceipt:hasProvisioningProfile:)``,
    /// ``hasSandboxReceipt(at:)`` and ``containsProvisioningProfile(at:relativePath:)``
    /// instead — the same split
    /// `AnalyticsBootstrap.watchOSOSSuperProperties(systemVersion:)` uses to
    /// keep its own platform gate out of the testable part.
    static let current: BuildEnvironment = {
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

        // `appStoreReceiptURL` is deprecated for Swift only, from iOS 18.0
        // (`NSBundle.h`, under `#if defined(__swift__)`), in favour of
        // StoreKit's `AppTransaction.shared`. This app's floor is 18.6, so the
        // call warns unconditionally. It is kept anyway, for now: reading the
        // receipt's *name* is synchronous and infallible, while
        // `AppTransaction.shared` is `async throws` and can fail with no
        // network — and this is read during `SentrySDK.start`, on the launch
        // path, where neither suspending nor failing is acceptable. Revisiting
        // it means giving this an async form, which is its own change.
        return BuildEnvironment(
            isDebugBuild: isDebugBuild,
            isSimulator: isSimulator,
            hasSandboxReceipt: hasSandboxReceipt(at: Bundle.main.appStoreReceiptURL),
            hasProvisioningProfile: hasProvisioningProfile(in: .main)
        )
    }()
}

extension BuildEnvironment {
    /// Classifies a build from the four facts that separate the cases.
    ///
    /// Order is the substance of this initializer, so each arm is worth stating:
    ///
    /// 1. The simulator wins outright. It is a property of where the build is
    ///    *running*, and it survives any configuration choice — where the other
    ///    three facts describe how the binary was built. Ignoring that ordering
    ///    is how simulator crashes reached `production` in the first place: the
    ///    WXYC scheme's Test action builds `Debug TestFlight`, whose bundle id is
    ///    the release one, `org.wxyc.iphoneapp`, so neither the bundle id nor
    ///    the configuration name identifies a simulator run (Sentry IOS-41).
    /// 2. A debug build that got past the first arm is on real hardware, which
    ///    means someone ran it from Xcode. Both `Debug` and `Debug TestFlight`
    ///    define `DEBUG` and both land here.
    /// 3. What remains is a release build, and the receipt is the only thing
    ///    that separates a beta tester from a real one. It has to be: the scheme
    ///    archives TestFlight and App Store builds from the same `Release`
    ///    configuration, so no compile-time fact tells them apart.
    /// 4. A release build with no receipt is still not necessarily a real user.
    ///    The scheme's *Profile* action builds `Release` too, so profiling a
    ///    device — the thing you do to chase a hang — used to file as production
    ///    traffic. Every install that did not come from the store carries an
    ///    embedded provisioning profile; a store build never does.
    /// 5. Only a release build with neither is a real user.
    ///
    /// The receipt is checked before the profile, and the order is deliberate.
    /// A sandbox receipt is *positive* evidence of TestFlight, whereas a missing
    /// profile is only indirect evidence about it — and whether TestFlight
    /// strips the profile is not a thing this code should have to be right
    /// about. Receipt-first classifies TestFlight correctly either way.
    ///
    /// Note this is the opposite of the order sentry-cocoa itself uses for its
    /// `app.build_type` tag, which checks the profile first
    /// (`SentryCrashMonitor_System.m`). The divergence is intended, and on a
    /// build carrying both it is visible: Sentry will show
    /// `environment: testflight` beside `app.build_type: adhoc`. `environment`
    /// answers "is this a real user", and a TestFlight tester is the more
    /// useful answer to that than how the binary happened to be signed.
    ///
    /// - Parameters:
    ///   - isDebugBuild: Whether `DEBUG` was defined when this was compiled.
    ///   - isSimulator: Whether the build targets the simulator.
    ///   - hasSandboxReceipt: Whether the App Store receipt is the sandbox one.
    ///   - hasProvisioningProfile: Whether a provisioning profile is bundled.
    init(
        isDebugBuild: Bool,
        isSimulator: Bool,
        hasSandboxReceipt: Bool,
        hasProvisioningProfile: Bool
    ) {
        if isSimulator {
            self = .simulator
        } else if isDebugBuild {
            self = .debug
        } else if hasSandboxReceipt {
            self = .testflight
        } else if hasProvisioningProfile {
            self = .adhoc
        } else {
            self = .production
        }
    }

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

    /// Where the provisioning profile sits inside the app bundle, relative to
    /// the bundle root.
    ///
    /// The one place the platform genuinely differs. A Mac Catalyst app is a
    /// macOS-style bundle, so both halves of the path change: the file is named
    /// `embedded.provisionprofile`, and it sits in `Contents/` rather than at
    /// the bundle root. Verified against real bundles on disk, this app's own
    /// shipped Mac build among them.
    ///
    /// Spelled as an explicit relative path rather than a
    /// `Bundle.url(forResource:withExtension:)` lookup, and that is load-bearing
    /// rather than stylistic: resource lookup searches the bundle's *resource*
    /// directory, which on a macOS-style bundle is `Contents/Resources` — so it
    /// cannot see a profile in `Contents` no matter which extension it is given.
    /// Measured against `/Applications/WXYC.app`, both
    /// `path(forResource:ofType:)` and `url(forResource:withExtension:)` return
    /// nil for the profile that is demonstrably there. Fixing only the extension
    /// would have left Catalyst just as broken.
    static var provisioningProfileBundlePath: String {
        #if targetEnvironment(macCatalyst)
        "Contents/embedded.provisionprofile"
        #else
        "embedded.mobileprovision"
        #endif
    }

    /// Whether the bundle carries an embedded provisioning profile, i.e. it was
    /// installed by some route other than the store.
    ///
    /// Xcode-installed, ad-hoc and enterprise builds all ship one; the store
    /// strips it during processing. Takes the bundle so a test can point at one
    /// that does not have it — `Bundle.main` under a test runner is not the app
    /// bundle.
    ///
    /// - Parameter bundle: The bundle to inspect, normally `.main`.
    /// - Returns: `true` when a provisioning profile is bundled.
    static func hasProvisioningProfile(in bundle: Bundle) -> Bool {
        containsProvisioningProfile(at: bundle.bundleURL, relativePath: provisioningProfileBundlePath)
    }

    /// Whether a file exists at `relativePath` inside the bundle at `bundleURL`.
    ///
    /// A plain `stat`, deliberately. The `Bundle.url(forResource:)` this
    /// replaced went through CFBundle's resource cache, which builds a directory
    /// enumeration and localization table for the whole bundle on first use:
    /// measured at 1.6–2.1 ms cold against the built `WXYC.app`, versus 11–19 µs
    /// for this. Nothing warms CFBundle before `WXYCApp.init()` — every other
    /// `forResource:` site in the app is a `Bundle.module` lookup against a
    /// nested bundle with its own cache — so the cold number is the one paid, on
    /// the main thread, on every launch. Splitting the path out from
    /// ``hasProvisioningProfile(in:)`` also makes both bundle layouts reachable
    /// from a test on one platform.
    ///
    /// - Parameters:
    ///   - bundleURL: The bundle's root, i.e. `Bundle.bundleURL`.
    ///   - relativePath: Path within the bundle, normally
    ///     ``provisioningProfileBundlePath``.
    /// - Returns: `true` when a file exists there.
    static func containsProvisioningProfile(at bundleURL: URL, relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: bundleURL.appending(path: relativePath).path)
    }

    private static let sandboxReceiptName = "sandboxReceipt"
}
