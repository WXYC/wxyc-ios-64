//
//  AppBootstrap.swift
//  WXYC
//
//  One-time launch setup — analytics, Sentry, and error reporting — extracted
//  from WXYCApp so the iOS and native-macOS @main entry points share exactly one
//  bootstrap path and can't drift. The Sentry launch-profiling policy (pinned by
//  SentryLaunchProfilingGateTests) lives here too; the network-tracking options
//  branch on macOS to avoid the SCNetworkReachability local-network prompt.
//
//  Created by Jake Bromberg on 08/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AppServices
import Caching
import Core
import Foundation
import Logger
import Sentry

enum AppBootstrap {
    static func setUpAnalytics() {
        AnalyticsBootstrap.start(
            apiKey: AppConfiguration.defaults.posthogApiKey,
            host: AppConfiguration.defaults.posthogHost
        )
    }

    static func setUpSentry() {
        // Decided here rather than inside the configuration closure because it
        // is not a pure read: saying yes spends one launch from a budget. See
        // ``consumeLaunchProfileBudget(defaults:environment:now:)``.
        let profileAppLaunch = Self.consumeLaunchProfileBudget()

        SentrySDK.start { options in
            options.dsn = AppConfiguration.sentryDsn

            // Unset, the SDK defaults this to "production" — so every simulator
            // run and every Xcode launch was filing under real user traffic, and
            // triage on the `environment` tag was worthless.
            //
            // Computed rather than hardcoded per configuration because no single
            // build-time fact separates the five cases; two of them can only be
            // told apart at runtime. `BuildEnvironment` documents the precedence,
            // the evidence behind each case, and the tests that pin them.
            options.environment = BuildEnvironment.current.rawValue

            options.enableAutoSessionTracking = true
            options.tracesSampleRate = NSNumber(value: Self.baseTracesSampleRate)
            options.enableUIViewControllerTracing = false  // SwiftUI app, no UIKit VCs
            #if os(macOS)
            // Sentry's SCNetworkReachability probing triggers macOS's
            // "find devices on local networks" permission prompt, so the
            // native Mac app keeps network tracking and breadcrumbs off.
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            #else
            options.enableNetworkTracking = true
            #endif
            options.enableSwizzling = true

            // App-launch profiling for WXYC/wxyc-ios-64#949's cold-launch
            // measurement. What bounds it — TestFlight, a five-launch budget
            // and a date — is on `shouldProfileAppLaunch`; why the sampler is
            // on `tracesSampleRate`. What is only true here is which SDK
            // surface this uses, and why it is not the obvious one.
            //
            // Not the `enableAppLaunchProfiling` boolean this line used to set
            // to `false`. On sentry-cocoa 8.58.4 that property is deprecated in
            // favour of `SentryProfileOptions`, and the deprecation is
            // load-bearing rather than cosmetic. `profilesSampleRate` defaults
            // to nil and this file never sets it, which puts the SDK in
            // continuous-profiling mode; there `sentry_shouldProfileNextLaunch`
            // returns the deprecated flag's own value and the launch starts
            // `SentryContinuousProfiler` with nothing to stop it
            // (`SentryLaunchProfiling.m`). Flipping the old flag would not have
            // collected nothing — it would have collected forever, a worse
            // version of the memory concern the old comment warned about.
            // Deleting the explicit `false` is a no-op: the SDK never assigns
            // that ivar, so it is already NO.
            //
            // `configureProfiling` is the documented replacement and is bounded:
            //   - `profileAppStarts` starts the profiler from
            //     `+[SentryProfiler load]`, before `main`.
            //   - `lifecycle = .trace` ties each profile to a root span, so it
            //     stops when that span ends. The launch profile's span is the
            //     tracer the launch-profile path builds for itself — not the
            //     `enableAutoPerformanceTracing` app-start transaction, which
            //     `enableUIViewControllerTracing = false` above means nothing
            //     ever creates — and it ends inside `SentrySDK.start`. But
            //     `.trace` is not launch-only: every *sampled* root span after
            //     launch profiles for its duration too, which on TestFlight is
            //     5% of the UI interactions swizzling reports — for as long as
            //     this branch keeps installing `configureProfiling` at all,
            //     which `launchProfileBudget` is what stops.
            //   - `sessionSampleRate` defaults to 0 — silently sampling nothing
            //     rather than erroring — so 1.0 is what makes it collect at all.
            if profileAppLaunch {
                options.configureProfiling = { profiling in
                    profiling.profileAppStarts = true
                    profiling.lifecycle = .trace
                    profiling.sessionSampleRate = 1.0
                }
                options.tracesSampler = {
                    NSNumber(value: Self.tracesSampleRate(
                        forNextAppLaunch: $0.transactionContext.forNextAppLaunch
                    ))
                }
            }

            // Disabled to reduce memory overhead: file I/O tracing generates
            // hundreds of spans from disk cache reads without actionable signal.
            options.enableFileIOTracing = false

            // Disable auto-capture of failed HTTP requests. The stream server returns 503
            // during outages, and each reconnect retry auto-generates a separate Sentry event
            // (up to 10-20 per outage). Stream errors are already reported to PostHog via
            // StreamErrorEvent and appear as Sentry breadcrumbs via SentryBreadcrumbDestination.
            options.enableCaptureFailedRequests = false

            // Structured server-side logs. Forwarded from the Logger via
            // SentryLogsDestination at info-and-above.
            options.experimental.enableLogs = true

            // App-hang tracking V2, reporting only fully-blocking hangs. V2 can
            // tell a fully-blocking hang (main thread stuck, not a frame
            // rendered) from a non-fully-blocking one, and the SDK's own header
            // is explicit that the latter "can have a stacktrace that doesn't
            // highlight the exact blocking location" — which is precisely the
            // noise that fragmented these issues. Over 30 days, 1207 hang
            // events became 68 issues, 40 of them holding a single event.
            // Non-fully-blocking hangs are dropped before an event is even
            // created, so they cost nothing downstream.
            options.enableAppHangTrackingV2 = true
            options.enableReportNonFullyBlockingAppHangs = false

            // `appHangTimeoutInterval` is deliberately left at its 2.0 default.
            // Raising it is the obvious way to quieten hang reports, and the
            // reason not to is that it hides the cold-launch regression this
            // option exists to catch. Not, as this comment used to argue, that
            // the `device.class` split across those 1207 events (high 1115 /
            // medium 91 / low 0) proves a flagship-only fleet: Sentry rarely
            // classifies a modern iPhone `low`, and #949's own IOS-42 evidence
            // includes an iPhone11,8 classified `medium`. See git history.

            // Regrouping the remaining hangs belongs to Sentry's server-side
            // Stack Trace Rules, not to a client `beforeSend`, and there is
            // deliberately no `beforeSend` here. A client fingerprint was built
            // and measured before being removed: `beforeSend` runs before
            // upload, and the SDK only symbolicates when `options.debug` is on
            // (`SentryThreadInspector` sets `symbolicate = options.debug`), so
            // `frame.function` is nil on every frame of every Release build —
            // any stack-derived fingerprint degenerates to one bucket in the
            // builds that matter. Worse, a custom fingerprint without a
            // `{{ default }}` token replaces server-side grouping outright,
            // which would put those Stack Trace Rules out of reach until the
            // next release. See git history for the full write-up.

            #if DEBUG
            options.debug = true
            // Frame tracking logs a debug line per slow frame (SentryFramesTracker),
            // which floods the console during any animation. Keep debug output but
            // raise the floor to warnings so the SDK stays quiet in normal use.
            options.diagnosticLevel = .warning
            #endif
        }
    }

    /// Whether app-launch profiling should be armed for the launch *after*
    /// this one. Split out of `setUpSentry()` so the policy is testable
    /// without booting the SDK — the same shape `BuildEnvironment.current`
    /// itself uses to keep its own platform gate out of the untestable part.
    ///
    /// Three conditions, because WXYC/wxyc-ios-64#949 asks for "one TestFlight
    /// build" of profiling and `configureProfiling` on its own delivers
    /// something quite different. `sentry_configureLaunchProfilingForNextLaunch`
    /// re-runs at the end of *every* `SentrySDK.start`, so an unconditional
    /// arm rewrites the launch-profile config file forever and every launch
    /// pays for a pre-`main` sampler. Each condition below closes one way that
    /// could outlive the measurement:
    ///
    /// - **`environment == .testflight`** keeps it off App Store traffic
    ///   entirely, and off `debug`/`simulator`/`adhoc`, which are not the
    ///   traffic #949 is measuring.
    /// - **``launchProfileBudget``** bounds what any one install pays, in both
    ///   launch time and hang-report volume.
    /// - **``launchProfilingExpiry``** is what turns the whole thing off
    ///   without shipping anything. A build number would not: it stops the
    ///   *next* build, never the pinned one, and a TestFlight build lives on
    ///   testers' phones long after it is superseded.
    ///
    /// The conditions are independent on purpose — any one of them going false
    /// disarms, and the SDK deletes the config file rather than leaving a
    /// stale one behind (`sentry_shouldProfileNextLaunch` returning `NO` calls
    /// `removeAppLaunchProfilingConfigFile`).
    nonisolated static func shouldProfileAppLaunch(
        environment: BuildEnvironment,
        armedLaunches: Int,
        now: Date
    ) -> Bool {
        environment == .testflight
            && armedLaunches < launchProfileBudget
            && now < launchProfilingExpiry
    }

    /// How many launches one install may arm before it stops on its own.
    ///
    /// #949 needs one usable cold-launch profile; five is the margin for the
    /// ways a given launch yields a poor one — a warm start moments after a
    /// kill, a launch straight into the background, a tester who force-quits
    /// mid-render. With a handful of testers that puts the expected profile
    /// count comfortably above one. What it buys in return is a ceiling on two
    /// costs, both of which land inside the launch window #949 is measuring:
    ///
    /// 1. **The sampler's own cost.** `SentrySamplingProfiler` runs at 101 Hz
    ///    and `thread_suspend`s the main thread for a `thread_get_state` plus
    ///    one `vm_read_overwrite` per frame, ≤128 frames
    ///    (`SentryBacktrace.cpp`). Order 1% of main-thread time, plus the
    ///    pre-`main` `CADisplayLink` + `pthread_create` + `clock_alarm` the
    ///    profiler installs on the way up.
    /// 2. **A wider hang-observation window.** Not the mechanism it looks
    ///    like: app-hang V2 does not round-trip the main queue the way V1
    ///    does (`SentryANRTrackerV1.m` dispatches, `SentryANRTrackerV2.m`
    ///    does not), it reads a frame-delay ledger the main thread writes, and
    ///    its watchdog is skipped by the profiler twice over — by the
    ///    `io.sentry` thread-name rule in `SentryThreadMetadataCache.cpp` and
    ///    by `isIdle()` while it sleeps. So the sampler does not lengthen a
    ///    measured hang. What it does do is start `SentryFramesTracker`
    ///    pre-`main` instead of at `SentrySDK.start`, and
    ///    `SentryDelayedFramesTracker` refuses to score a window it has no
    ///    history for. A profiled launch therefore reports launch-window
    ///    hangs an unprofiled one silently discards. Those are real 2 s
    ///    stalls, and for #949 seeing them is the point — but IOS-42's rate
    ///    on a profiled build is not comparable to its rate on an unprofiled
    ///    one, so this bounds how much traffic carries the wider window.
    ///    (`environment` is `testflight` on exactly those launches, so the
    ///    comparison can also just exclude them.)
    nonisolated static let launchProfileBudget = 5

    /// The date after which no launch arms, whatever the budget says.
    ///
    /// 2026-09-30T00:00:00Z, ~6 weeks out: long enough for a build to reach
    /// TestFlight and accumulate launches, short enough that it cannot outlive
    /// the investigation. Spelled as an epoch so it costs no date parsing on
    /// the launch path; `SentryLaunchProfilingGateTests` pins the number to
    /// the calendar date so the two cannot drift apart.
    ///
    /// A wrong device clock can move this either way. That is acceptable
    /// because it cannot unbound anything: ``launchProfileBudget`` still caps
    /// a skewed-early device at five launches, and a skewed-late one simply
    /// contributes no profile.
    nonisolated static let launchProfilingExpiry = Date(timeIntervalSince1970: 1_790_726_400)

    /// `UserDefaults` key holding how many launches this install has armed.
    /// Dotted and type-prefixed like `CacheMigrationManager`'s keys, because
    /// the App Group suite it lives in is shared with the widget and the Share
    /// extension.
    nonisolated static let armedLaunchesDefaultsKey = "SentryLaunchProfiling.armedLaunches"

    /// Asks ``shouldProfileAppLaunch(environment:armedLaunches:now:)`` and, on
    /// yes, records that this launch spent one of the budget.
    ///
    /// Counts *arms*, not profiles, which is the conservative direction: an
    /// arm that never gets consumed — the app is deleted, or `SentrySDK.start`
    /// runs again before the next cold launch — still costs a slot. What it
    /// cannot do is under-count, so the budget is a true ceiling on profiled
    /// launches.
    ///
    /// The off-by-one is the SDK's, not ours: launch *N* decides for launch
    /// *N+1*, so a fresh install is never profiled on its first launch and a
    /// budget of five profiles launches 2 through 6.
    ///
    /// The `defaults` read happens on every launch in every environment, so it
    /// deliberately uses the App Group suite rather than
    /// `UserDefaults.standard`: `CacheMigrationManager.migrateIfNeeded()` is
    /// the first statement of `init()` and reads `UserDefaults.wxyc`, so that
    /// domain is already faulted in by the time `setUpSentry()` runs and this
    /// costs a dictionary lookup. Nothing on the launch path touches the
    /// standard domain before this point, so reading it here would have added
    /// a `cfprefsd` round trip to the cold-launch path of an issue about
    /// cold-launch cost. The write happens at most ``launchProfileBudget``
    /// times per install.
    nonisolated static func consumeLaunchProfileBudget(
        defaults: DefaultsStorage = UserDefaults.wxyc,
        environment: BuildEnvironment = .current,
        now: Date = .now
    ) -> Bool {
        let armedLaunches = defaults.integer(forKey: armedLaunchesDefaultsKey)

        guard shouldProfileAppLaunch(
            environment: environment,
            armedLaunches: armedLaunches,
            now: now
        ) else {
            return false
        }

        defaults.set(armedLaunches + 1, forKey: armedLaunchesDefaultsKey)
        return true
    }

    /// The share of transactions traced in the ordinary case. Named because
    /// an installed `tracesSampler` shadows `tracesSampleRate` outright, so
    /// editing one and not the other would change tracing volume silently.
    nonisolated static let baseTracesSampleRate = 0.05

    /// The trace sample rate for one sampling decision, while app-launch
    /// profiling is armed.
    ///
    /// `forNextAppLaunch` is set by exactly one caller inside the SDK: the
    /// synthetic `app.launch` transaction Sentry samples at the end of
    /// `SentrySDK.start` to decide whether the *next* launch is profiled, and
    /// persists to disk for that launch to consume. It gets 1.0, because at
    /// ``baseTracesSampleRate`` the profile arrives about once per twenty
    /// launches — fine at App Store scale, and not something a TestFlight
    /// population of a handful of testers can be relied on to reach. That is
    /// the failure this exists to prevent, and it is a silent one: the change
    /// merges looking correct and #949 stays blocked.
    ///
    /// Raising `tracesSampleRate` itself for TestFlight would have armed the
    /// profile just as well, and was rejected: it also multiplies every
    /// unrelated TestFlight transaction by twenty, and #949's own triage
    /// reads those same series. Every other decision keeps drawing at
    /// ``baseTracesSampleRate`` — though a sampler does pre-empt
    /// `parentSampled`, which is moot here: this app originates traces and
    /// never continues an inbound one.
    ///
    /// `nonisolated` because `SentryOptions.tracesSampler` is
    /// `NS_SWIFT_SENDABLE` and Sentry calls it off the main thread, while
    /// `WXYCApp` infers `@MainActor` from `App`. Without it the call is a
    /// warning rather than an error only because Sentry's headers import
    /// `@preconcurrency`.
    nonisolated static func tracesSampleRate(forNextAppLaunch: Bool) -> Double {
        forNextAppLaunch ? 1.0 : baseTracesSampleRate
    }

    static func setUpErrorReporting() {
        ErrorReporting.shared = CompositeErrorReporter()
        Logger.addDestination(SentryBreadcrumbDestination())
        Logger.addDestination(SentryLogsDestination())
    }
}
