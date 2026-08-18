//
//  WXYCApp.swift
//  WXYC
//
//  Main app entry point. Owns one-time `init()` setup (caches, analytics, Sentry,
//  Siri donation), Scene-level lifecycle observation (scenePhase, review-request,
//  picker exit), and the Scene wiring. Per-window View-level lifecycle, command
//  menus, and the background-refresh task body live in their own files.
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppServices
import Analytics
import Artwork
import AVFoundation
import Caching
import Core
import Intents
import Logger
import MusicShareKit
import Observation
import Playback
import PlaybackCore
import PlayerHeaderView
import Playlist
import Sentry
import StoreKit
import SwiftUI
import Wallpaper
import WXUI
#if DEBUG
import DebugPanel
#endif

private enum SettingsBundleKeys {
    static let clearArtworkCache = "clear_artwork_cache"
}

@main
struct WXYCApp: App {
    // Returns PlayMediaIntentHandler for a directly-dispatched INPlayMediaIntent
    // — the media-suggestion tile's background entry point (#829). See
    // AppDelegate.swift for the constraints on what this type may implement.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = Singletonia.shared
    @State private var foregroundRefreshTask: Task<Void, Never>?
    @State private var cacheCleanupTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    init() {
        // Cache migration - purge if version changed
        CacheMigrationManager.migrateIfNeeded()
        
        #if DEBUG
        // Migrate existing PNG artwork cache entries to HEIF for reduced size
        Task {
            await CacheCoordinator.migratePngCacheToHeif()
        }
        #endif

        // Enable battery monitoring for thermal context
        DeviceContext.enableBatteryMonitoring()

        // Configure MusicShareKit for RequestService. The keychainAccessGroup
        // must match what the Share Extension passes so a session cached by
        // one target is readable by the other (issue #336). Dropping it
        // silently regresses to per-process keychain storage.
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: AppConfiguration.defaults.requestOMaticUrl,
            authBaseURL: AppConfiguration.defaults.apiBaseUrl,
            keychainAccessGroup: AppConfiguration.keychainAccessGroup,
            featureFlagProvider: PostHogFeatureFlagProvider.shared,
            analyticsService: StructuredPostHogAnalytics.shared
        ))

        // Analytics, Sentry, and error reporting setup
        setUpAnalytics()
        setUpSentry()
        setUpErrorReporting()
        StructuredPostHogAnalytics.shared.capture(AppLaunch(
            hasUsedThemePicker: appState.themePickerState.persistence.hasEverUsedPicker
        ))

        // Note: AVAudioSession category is set by AudioPlayerController when playback starts.
        // Setting it here at launch would interrupt other apps' audio unnecessarily.

        // UIKit appearance setup
        #if os(iOS)
        UINavigationBar.appearance().barStyle = .black
        #endif
        
        // Fetch backend configuration (upgrades artwork service with Discogs fallback)
        let appState = self.appState
        Task { await appState.fetchConfiguration() }

        // Declare media-suggestion eligibility (#828): publishes an
        // INMediaUserContext and seeds INUpcomingMediaManager with the
        // canonical WXYC play intent. Own Task, on the main actor — this is
        // app-global system state, the same category HandoffActivityManager
        // already models as main-actor work — deliberately *not* routed
        // through donateSiriIntent()'s Task below, which is off the main
        // actor on purpose (#740). Gated to match MediaSuggestionService's
        // own gate: the WXYC target builds for Mac Catalyst, which inherits
        // iOS availability, so a bare os(iOS) check would compile and run
        // this where the suggestion surface doesn't exist.
        #if os(iOS) && !targetEnvironment(macCatalyst)
        Task {
            MediaSuggestionService().register()
        }
        #endif

        // Siri intent donation. Schedules a Task and returns immediately — see
        // donateSiriIntent()'s doc comment for why this can never block init().
        Self.donateSiriIntent()
    }
        
    var body: some Scene {
        WindowGroup {
            ThemePickerContainer(
                configuration: appState.themeConfiguration,
                pickerState: appState.themePickerState
            ) {
                ZStack {
                    RootTabView()
                        .environment(appState)
                        .environment(\.playlistService, appState.playlistService)
                        .forceLightStatusBar()
                        .crossfadeColorSchemeTransitions()
                        .modifier(AppLifecycleModifier(appState: appState))

                    #if DEBUG
                    DebugHUD()
                    if ThemeDebugState.shared.showOverlay {
                        ThemeDebugOverlay(configuration: appState.themeConfiguration)
                    }
                    #endif
                }
            }
        }
        // Scene-level lifecycle observation (kept here rather than inside
        // AppLifecycleModifier so multi-window Catalyst doesn't fire them per
        // window). `initial: true` delivers the phase the app launches into —
        // this is the app's only producer of foreground state, and no phase
        // *change* follows a launch to report it otherwise.
        .onChange(of: scenePhase, initial: true) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: appState.reviewRequestService.shouldRequestReview) { _, shouldRequest in
            if shouldRequest {
                requestReview()
                appState.reviewRequestService.didRequestReview()
            }
        }
        .onChange(of: appState.themePickerState.isActive) { wasActive, isActive in
            // Picker exited (was active, now inactive): re-extract palette for
            // the newly selected theme so the home screen reflects it.
            if wasActive && !isActive {
                WallpaperPaletteExtraction.extract(into: appState.themeConfiguration)
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefreshController.taskIdentifier)) {
            await BackgroundRefreshController.handleRefresh(appState: appState)
        }
        #if targetEnvironment(macCatalyst)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            WXYCCommandMenus(appState: appState)
        }
    }

    // MARK: - Scene phase

    /// Drives every lifecycle consumer off what the phase *means* for on-screen
    /// state rather than off the phase itself — `.inactive` is deliberately
    /// inert (see `ForegroundVisibility` for the story), and every consumer
    /// here shares that one classification because a second `switch` on the
    /// raw phase is how a future consumer would reintroduce the bug with the
    /// tests still green.
    ///
    /// The app's sole producer of foreground state: called for every phase
    /// change and, via `initial: true`, once with `oldPhase == newPhase` for
    /// the phase the window appeared into. Per-window `.onAppear` deliberately
    /// sends nothing — a second window appearing into an `.inactive` scene
    /// while another stays `.active` would latch app-wide state false with no
    /// phase change coming to correct it (multi-window Catalyst), whereas this
    /// Scene-level aggregate can't read a wrong per-window value.
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        // The initial delivery (`oldPhase == newPhase`) is not a foreground
        // *return*: the arms below are change-edge work (analytics, player
        // reconciliation, refresh), so it routes the phase to the services and
        // does nothing else.
        if oldPhase != newPhase {
            switch ForegroundVisibility(entering: newPhase) {
            case .offScreen:
                StructuredPostHogAnalytics.shared.capture(AppEnteredBackground(
                    isPlaying: AudioPlayerController.shared.isPlaying
                ))
                AudioPlayerController.shared.handleAppDidEnterBackground()
                AdaptiveQualityController.shared.handleBackgrounded()

            case .onScreen:
                AudioPlayerController.shared.handleAppWillEnterForeground()
                AdaptiveQualityController.shared.handleForegrounded()
                BackgroundRefreshController.scheduleNext()
                // Cancel previous tasks to avoid duplicated work from rapid phase changes
                foregroundRefreshTask?.cancel()
                cacheCleanupTask?.cancel()
                // Returning users see fresh data immediately rather than waiting
                // for the next periodic fetch cycle.
                foregroundRefreshTask = refreshPlaylistIfCacheExpired()
                // Honour the "Clear Artwork Cache" toggle from the Settings app.
                cacheCleanupTask = handleSettingsBundleCacheClear()

            case .noChange:
                break
            }
        }

        // After the player hooks above, deliberately: WidgetStateService's
        // false → true edge snapshots playback state and spends a budgeted
        // timeline reload, so it must see the session
        // `handleAppWillEnterForeground()` has already reconciled, not the one
        // it is about to replace.
        appState.setScenePhase(newPhase)
    }

    private func refreshPlaylistIfCacheExpired() -> Task<Void, Never> {
        Task {
            let isExpired = await appState.playlistService.isCacheExpired()
            if isExpired {
                Log(.info, category: .general, "Cache expired while backgrounded - triggering foreground refresh")
                _ = await appState.playlistService.fetchAndCachePlaylist()
                // The Spotlight batch backfill normally piggybacks on the PlaylistService
                // broadcast this fetch triggers (see Singletonia.startSpotlightDonation).
                // A rapid .active → .background → .active cycle can cancel this Task
                // mid-fetch; PlaylistService.ingest's cancellation guard would skip the
                // broadcast for that cycle, and the next 30s periodic fetch picks it up.

            }
        }
    }

    private func handleSettingsBundleCacheClear() -> Task<Void, Never>? {
        guard UserDefaults.standard.bool(forKey: SettingsBundleKeys.clearArtworkCache) else {
            return nil
        }

        return Task {
            let sizeBeforeClear = await CacheCoordinator.AlbumArt.totalSize()
            await CacheCoordinator.AlbumArt.clearAll()
            UserDefaults.standard.set(false, forKey: SettingsBundleKeys.clearArtworkCache)

            Log(.info, category: .general, "Cleared artwork cache via Settings toggle (\(sizeBeforeClear) bytes)")
            StructuredPostHogAnalytics.shared.capture(ArtworkCacheCleared(
                source: "settings_toggle",
                sizeBytes: sizeBeforeClear
            ))
        }
    }

    // MARK: - Setup

    private func setUpAnalytics() {
        AnalyticsBootstrap.start(
            apiKey: AppConfiguration.defaults.posthogApiKey,
            host: AppConfiguration.defaults.posthogHost
        )
    }

    private func setUpSentry() {
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
            options.enableNetworkTracking = true
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
    nonisolated static let armedLaunchesDefaultsKey = "sentry_launch_profile_armed_launches"

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
    /// The `defaults` read happens on every launch in every environment, which
    /// is affordable: `CacheMigrationManager.migrateIfNeeded()` earlier in
    /// `init()` has already faulted the standard domain in, leaving this a
    /// dictionary lookup. The write happens at most ``launchProfileBudget``
    /// times per install.
    nonisolated static func consumeLaunchProfileBudget(
        defaults: DefaultsStorage = UserDefaults.standard,
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

    private func setUpErrorReporting() {
        ErrorReporting.shared = CompositeErrorReporter()
        Logger.addDestination(SentryBreadcrumbDestination())
        Logger.addDestination(SentryLogsDestination())
    }

    // MARK: - Siri Intents

    /// Fire-and-forget: `makeSiriIntentInteraction()` — including the
    /// `UIImage.placeholder` compositing — runs inside this `Task`, off the
    /// main actor, so `init()` never blocks on it.
    ///
    /// Only the interaction-building half is `nonisolated`. `performDonation`
    /// hops back onto the main actor before touching `NSUserActivity`,
    /// because `becomeCurrent()` is a side effect on app-global system state
    /// that this codebase already models as main-actor work — see
    /// `HandoffActivityManager`'s `@MainActor CurrentActivityControlling`.
    /// Both `HandoffActivityManager.setPlaybackState(isPlaying:)` and this
    /// donation call `becomeCurrent()` on the same `WXYCUserActivity.play`
    /// activity type; leaving them unserialized across threads would let a
    /// cold-launch playback start race the still-in-flight donation and
    /// silently lose the Handoff-eligible activity to a last-writer-wins
    /// `becomeCurrent()` from a background thread (#740 review, finding 1).
    ///
    /// The explicit `nonisolated` on this function and on
    /// `makeSiriIntentInteraction()` is load-bearing, not decorative: this
    /// module builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
    /// (Xcode's Swift 6 "approachable concurrency" default), so a plain
    /// `static func` here — and the `Task { }` it creates, which inherits
    /// its *lexical* declaration's isolation — would otherwise default to
    /// running on the main actor. Verified empirically (#740): with no
    /// `nonisolated` anywhere in this chain, `MainActor.assertIsolated()`
    /// inside the `Task` did not trap, i.e. the placeholder compositing was
    /// still happening on the main actor, just one async hop later — a
    /// relocated hang, not a fixed one.
    ///
    /// `isolationProbe` and `donate` exist solely for
    /// `WXYCAppDonationEscapesMainActorTests`: `isolationProbe` confirms the
    /// real `Task` stays off the main actor without resorting to a
    /// crash-based check, and `donate` lets the test skip the real SiriKit
    /// donation / `becomeCurrent()` / PostHog capture entirely rather than
    /// firing them on every test run. Neither parameter changes production
    /// behavior — both default to exactly what shipped before they existed.
    nonisolated static func donateSiriIntent(
        isolationProbe: (@Sendable ((any Actor)?) -> Void)? = nil,
        donate: @escaping @Sendable (INInteraction) async -> Void = Self.performDonation
    ) {
        Task {
            isolationProbe?(#isolation)
            // Warm the placeholder here, first, so this Task — not
            // NowPlayingInfoCenterManager.mediaItemArtwork() on the main
            // actor (reached whenever a NowPlayingItem with nil artwork
            // arrives) — is the thread that pays for UIImage.placeholder's
            // first-access compositing. Whichever thread touches the
            // static let first absorbs the cost inside its swift_once; this
            // makes that thread a guarantee rather than a race (#740
            // review, finding 2).
            _ = UIImage.placeholder
            let interaction = makeSiriIntentInteraction()
            await donate(interaction)
        }
    }

    /// The real donation behavior `donateSiriIntent()` defaults to: donate
    /// to SiriKit, then hop onto the main actor to make the Handoff/Siri
    /// activity current and capture analytics. Factored out so tests can
    /// substitute a no-op instead (see `donateSiriIntent(isolationProbe:donate:)`).
    nonisolated private static func performDonation(_ interaction: INInteraction) async {
        do {
            try await interaction.donate()

            await MainActor.run {
                let activity = NSUserActivity(activityType: WXYCUserActivity.play)
                activity.title = "Play \(RadioStation.WXYC.name)"
                activity.isEligibleForPrediction = true
                activity.isEligibleForSearch = true
                // Defaults to true; without this, this launch-time activity —
                // becomeCurrent() with nothing playing yet — would advertise a
                // premature Handoff banner once NSUserActivityTypes declares
                // the type. HandoffActivityManager is the sole, playback-gated
                // source of the Handoff banner for this activity type.
                activity.isEligibleForHandoff = false
                activity.suggestedInvocationPhrase = "Play \(RadioStation.WXYC.name)"
                activity.userInfo = ["origin": "donateSiriIntent"]
                activity.becomeCurrent()

                StructuredPostHogAnalytics.shared.capture(SiriIntentDonated(
                    intentData: activity.description
                ))
            }
        } catch {
            ErrorReporting.shared.report(error, context: "WXYCApp: Failed to donate Siri intent")
        }
    }

    /// Builds the `INInteraction` `donateSiriIntent()` donates, including the
    /// placeholder artwork. Factored out of `donateSiriIntent()` so it runs —
    /// and can be tested — off the main actor. Explicitly `nonisolated` for
    /// the same reason as `donateSiriIntent()`: this module's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise isolate it
    /// to the main actor by default, which would force `donateSiriIntent()`'s
    /// (also `nonisolated`) `Task` to hop back onto the main actor just to
    /// call it — silently reintroducing the compositing work there (#740).
    /// This only pins the `Task`'s own isolation and this function's; it does
    /// not by itself guarantee every function `UIImage.placeholder` calls
    /// stays `nonisolated` — the compiler catches the naive regression
    /// (calling main-actor-isolated code from here fails to build), but a
    /// more indirect regression is out of this check's reach (#740 review,
    /// finding 5).
    nonisolated static func makeSiriIntentInteraction() -> INInteraction {
        let placeholder = UIImage.placeholder
        let artwork = INImage(imageData: placeholder.pngData()!)
        let intent = MediaIntentBuilder.makePlayMediaIntent(artwork: artwork)
        return INInteraction(intent: intent, response: nil)
    }
}

#Preview {
    ThemePickerContainer(
        configuration: ThemeConfiguration(),
        pickerState: ThemePickerState()
    ) {
        RootTabView()
            .environment(Singletonia.shared)
            .environment(\.playlistService, .preview)
            .preferredColorScheme(.light)
    }
}
