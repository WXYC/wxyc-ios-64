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

        // Configure MusicShareKit for RequestService
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: AppConfiguration.defaults.requestOMaticUrl,
            authBaseURL: AppConfiguration.defaults.apiBaseUrl,
            keychainAccessGroup: AppConfiguration.keychainAccessGroup,
            analyticsService: StructuredPostHogAnalytics.shared
        ))

        // Analytics, Sentry, and error reporting setup
        setUpAnalytics()
        setUpSentry()
        setUpErrorReporting()
        StructuredPostHogAnalytics.shared.capture(AppLaunch(
            hasUsedThemePicker: appState.themePickerState.persistence.hasEverUsedPicker,
            buildType: buildConfiguration()
        ))

        // Note: AVAudioSession category is set by AudioPlayerController when playback starts.
        // Setting it here at launch would interrupt other apps' audio unnecessarily.

        // UIKit appearance setup
        #if os(iOS)
        UINavigationBar.appearance().barStyle = .black
        
        // Force light status bar style
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
        #endif
        
        // Fetch backend configuration (upgrades artwork service with Discogs fallback)
        let appState = self.appState
        Task { await appState.fetchConfiguration() }

        // Siri intent donation
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
                        .environment(\.artworkService, appState.artworkService)
                        .environment(\.playbackController, AudioPlayerController.shared)
                        .environment(\.reviewRequestService, appState.reviewRequestService)
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
        // window).
        .onChange(of: scenePhase) { oldPhase, newPhase in
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
                AppLifecycleModifier.extractWallpaperPalette(into: appState.themeConfiguration)
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

    private func handleScenePhaseChange(from _: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            StructuredPostHogAnalytics.shared.capture(AppEnteredBackground(
                isPlaying: AudioPlayerController.shared.isPlaying
            ))
            AudioPlayerController.shared.handleAppDidEnterBackground()
            AdaptiveQualityController.shared.handleBackgrounded()
            appState.setForegrounded(false)

        case .inactive:
            appState.setForegrounded(false)

        case .active:
            AudioPlayerController.shared.handleAppWillEnterForeground()
            AdaptiveQualityController.shared.handleForegrounded()
            appState.setForegrounded(true)
            BackgroundRefreshController.scheduleNext()
            // Cancel previous tasks to avoid duplicated work from rapid phase changes
            foregroundRefreshTask?.cancel()
            cacheCleanupTask?.cancel()
            // Returning users see fresh data immediately rather than waiting
            // for the next periodic fetch cycle.
            foregroundRefreshTask = refreshPlaylistIfCacheExpired()
            // Honour the "Clear Artwork Cache" toggle from the Settings app.
            cacheCleanupTask = handleSettingsBundleCacheClear()

        @unknown default:
            break
        }
    }

    private func refreshPlaylistIfCacheExpired() -> Task<Void, Never> {
        Task {
            let isExpired = await appState.playlistService.isCacheExpired()
            if isExpired {
                Log(.info, category: .general, "Cache expired while backgrounded - triggering foreground refresh")
                _ = await appState.playlistService.fetchAndCachePlaylist()
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
            host: AppConfiguration.defaults.posthogHost,
            buildConfiguration: buildConfiguration()
        )
    }

    private func setUpSentry() {
        SentrySDK.start { options in
            options.dsn = AppConfiguration.sentryDsn
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

            #if DEBUG
            options.debug = true
            #endif
        }
    }

    private func setUpErrorReporting() {
        ErrorReporting.shared = CompositeErrorReporter()
        Logger.addDestination(SentryBreadcrumbDestination())
    }

    private func buildConfiguration() -> String {
        #if DEBUG
        return "Debug"
        #elseif TEST_FLIGHT
        return "TestFlight"
        #else
        return "Release"
        #endif
    }
    
    // MARK: - Siri Intents

    static func donateSiriIntent() {
        let placeholder = UIImage.placeholder
        let mediaItem = INMediaItem(
            identifier: "Play \(RadioStation.WXYC.name)",
            title: "Play \(RadioStation.WXYC.name)",
            type: .radioStation,
            artwork: INImage(imageData: placeholder.pngData()!)
        )
        let intent = INPlayMediaIntent(
            mediaItems: [mediaItem],
            mediaContainer: nil,
            playShuffled: nil,
            resumePlayback: false,
            playbackQueueLocation: .now,
            playbackSpeed: nil
        )
        intent.suggestedInvocationPhrase = "Play \(RadioStation.WXYC.name)"
        let interaction = INInteraction(intent: intent, response: nil)

        Task {
            do {
                try await interaction.donate()

                let activity = NSUserActivity(activityType: "org.wxyc.iphoneapp.play")
                activity.title = "Play \(RadioStation.WXYC.name)"
                activity.isEligibleForPrediction = true
                activity.isEligibleForSearch = true
                activity.suggestedInvocationPhrase = "Play \(RadioStation.WXYC.name)"
                activity.userInfo = ["origin": "donateSiriIntent"]
                activity.becomeCurrent()

                StructuredPostHogAnalytics.shared.capture(SiriIntentDonated(
                    intentData: activity.description
                ))
            } catch {
                ErrorReporting.shared.report(error, context: "WXYCApp: Failed to donate Siri intent")
            }
        }
    }
}

#Preview {
    ThemePickerContainer(
        configuration: ThemeConfiguration(),
        pickerState: ThemePickerState()
    ) {
        RootTabView()
            .environment(\.playlistService, .preview)
            .environment(\.artworkService, .preview)
            .environment(\.playbackController, AudioPlayerController.shared)
            .preferredColorScheme(.light)
    }
}
