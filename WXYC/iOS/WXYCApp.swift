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
        // Stands in for process launch. `init()` runs before any UI exists, so
        // this is within milliseconds of it, and it is captured by `beforeSend`
        // below to date every event against the launch it belongs to. A wall
        // clock deliberately, not a monotonic one: it is compared against
        // `event.timestamp`, which is also wall clock.
        let launchedAt = Date()

        SentrySDK.start { options in
            options.dsn = AppConfiguration.sentryDsn

            // Unset, the SDK defaults this to "production" — so every simulator
            // run and every Xcode launch has been filing under real user
            // traffic, and triage on the `environment` tag was worthless. Whole
            // issues turned out to be this machine: `BGTaskScheduler is not
            // available on this platform` (IOS-1S/20/1V, an API the Simulator
            // genuinely lacks) and the v2 playlist timeouts (IOS-2S/1T/24/3Y,
            // 100% on the debug bundle).
            //
            // Computed rather than hardcoded per configuration because no
            // single build-time fact separates the four cases. The scheme's
            // Test action builds `Debug TestFlight`, which carries the
            // *release* bundle id, so a simulator run can look shipped by
            // bundle id alone (IOS-41); and Archive builds TestFlight and App
            // Store from one `Release` configuration, so only the receipt tells
            // those two apart, at runtime. See `BuildEnvironment` for the
            // precedence and the tests that pin it.
            options.environment = BuildEnvironment.current.rawValue

            options.enableAutoSessionTracking = true
            options.tracesSampleRate = 0.05
            options.enableUIViewControllerTracing = false  // SwiftUI app, no UIKit VCs
            options.enableNetworkTracking = true
            options.enableSwizzling = true

            // Disabled to reduce memory overhead:
            // - App launch profiling accumulates 10-20MB of stack samples; use Instruments instead
            // - File I/O tracing generates hundreds of spans from disk cache reads without actionable signal
            options.enableAppLaunchProfiling = false
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
            // Dropping the non-fully-blocking half attacks that at the source;
            // `SentryEventFilters` regroups whatever still arrives.
            options.enableAppHangTrackingV2 = true
            options.enableReportNonFullyBlockingAppHangs = false

            // `appHangTimeoutInterval` is deliberately left at its 2.0 default.
            // Raising it is the obvious way to quieten hang reports and it is
            // the wrong one here: across those 1207 events the `device.class`
            // split was high 1115 / medium 91 / low 0. These are flagship
            // devices, so a >2 s stall is a real defect rather than an
            // underpowered-hardware artifact, and a higher threshold would hide
            // exactly the cold-launch regression this is meant to catch.

            // The app's only `beforeSend`. Runs on every event, so it is
            // written to return anything it does not recognise untouched — see
            // `SentryEventFilters` for the rules and for where to add the next
            // filter.
            options.beforeSend = { event in
                SentryEventFilters.beforeSend(event, launchedAt: launchedAt)
            }

            #if DEBUG
            options.debug = true
            // Frame tracking logs a debug line per slow frame (SentryFramesTracker),
            // which floods the console during any animation. Keep debug output but
            // raise the floor to warnings so the SDK stays quiet in normal use.
            options.diagnosticLevel = .warning
            #endif
        }
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
