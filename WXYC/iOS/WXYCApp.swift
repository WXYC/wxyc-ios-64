//
//  WXYCApp.swift
//  WXYC
//
//  Main app entry point defining the SwiftUI App lifecycle, service initialization,
//  background refresh scheduling, and environment injection for shared dependencies.
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppServices
import Analytics
import Artwork
import AVFoundation
import BackgroundTasks
import Caching
import Core
import Intents
import Logger
import MusicShareKit
import Observation
import OpenNSFW
import Playback
import PlayerHeaderView
import Playlist
import PostHog
import Secrets
import StoreKit
import SwiftUI
import Wallpaper
import WXUI
#if DEBUG
import DebugPanel
#endif

// MARK: - Settings Bundle Keys

private enum SettingsBundleKeys {
    static let clearArtworkCache = "clear_artwork_cache"
}

@main
struct WXYCApp: App {
    @State private var appState = Singletonia.shared
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

        // Seed OpenNSFW model to shared container for widget
        if let bundleURL = Bundle.main.url(forResource: "OpenNSFW", withExtension: "mlmodelc") {
            ModelSeeder.seedIfNeeded(bundleModelURL: bundleURL)
        }
        
        // Enable battery monitoring for thermal context
        DeviceContext.enableBatteryMonitoring()

        // Configure MusicShareKit for RequestService
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: Secrets.requestOMatic,
            authBaseURL: Secrets.apiBaseUrl,
            spotifyClientId: Secrets.spotifyClientId,
            spotifyClientSecret: Secrets.spotifyClientSecret,
            analyticsService: StructuredPostHogAnalytics.shared
        ))

        // Analytics setup
        setUpAnalytics()
        setUpQualityAnalytics()
        setUpThemePickerAnalytics()
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
                        .frame(maxWidth: 440)
                        .environment(appState)
                        .environment(\.playlistService, appState.playlistService)
                        .environment(\.artworkService, appState.artworkService)
                        .environment(\.playbackController, AudioPlayerController.shared)
                        .environment(\.reviewRequestService, appState.reviewRequestService)
                        .forceLightStatusBar()
                        .onAppear {
                            setUpQuickActions()
                            appState.setForegrounded(true)
                            appState.startWidgetStateService()
                            appState.startReviewRequestTracking()

                            // Extract wallpaper palette on first launch if not cached
                            if appState.themeConfiguration.meshGradientPalette == nil {
                                extractWallpaperPalette()
                            }

                            // Force status bar to be light
#if os(iOS)
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first {
                                window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
                            }
#endif

                            // Start marketing mode if enabled via launch argument
                            if MarketingModeController.isEnabled {
                                MarketingModeController().start(
                                    playbackController: AudioPlayerController.shared,
                                    pickerState: appState.themePickerState,
                                    configuration: appState.themeConfiguration,
                                    playlistService: appState.playlistService
                                )
                            }
                        }
                        .onOpenURL { url in
                            handleURL(url)
                        }
                        .onContinueUserActivity("org.wxyc.iphoneapp.play") { userActivity in
                            handleUserActivity(userActivity)
                        }
                        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                            handleUserActivity(userActivity)
                        }

#if DEBUG
                    DebugHUD()
                    
                    if ThemeDebugState.shared.showOverlay {
                        ThemeDebugOverlay(configuration: appState.themeConfiguration)
                    }
#endif
                }
            }
        }
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
            // When picker exits (was active, now inactive), extract palette from new theme
            if wasActive && !isActive {
                extractWallpaperPalette()
            }
        }
        .backgroundTask(.appRefresh("com.wxyc.refresh")) {
            Log(.info, category: .general, "Background refresh started")

            // Fetch fresh playlist (this always fetches from network, ignoring cache)
            // and caches it with a 15-minute lifespan.
            // Note: Widget reload is handled by WidgetStateService observing playlist updates.
            let playlist = await appState.playlistService.fetchAndCachePlaylist()

            Log(.info, category: .general, "Background refresh completed successfully with \(playlist.entries.count) entries")

            StructuredPostHogAnalytics.shared.capture(BackgroundRefreshCompleted(
                entryCount: playlist.entries.count
            ))

            // Schedule the next refresh
            await MainActor.run {
                scheduleBackgroundRefresh()
            }
        }
        #if os(macOS)
        .defaultSize(width: 440, height: 800)
        #endif
        .commands {
                CommandMenu("Playback") {
                    Button("Play/Pause") {
                        AudioPlayerController.shared.toggle(reason: .keyboardShortcut)
                    }
                    .keyboardShortcut(.space, modifiers: [])
                }
                CommandMenu("Themes") {
                    Button("Toggle Theme Picker") {
                        toggleThemePicker()
                    }
                    .keyboardShortcut(.return, modifiers: [])

                    Button("Previous Theme") {
                        navigateToPreviousTheme()
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!appState.themePickerState.isActive)

                    Button("Next Theme") {
                        navigateToNextTheme()
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!appState.themePickerState.isActive)
                }
            #if DEBUG || DEBUG_TESTFLIGHT
                CommandMenu("Debug") {
                    Button("Trigger Background Refresh") {
                        Task {
                            Log(.info, category: .general, "Manual background refresh triggered")
                            let playlist = await appState.playlistService.fetchAndCachePlaylist()
                            Log(.info, category: .general, "Manual background refresh completed with \(playlist.entries.count) entries")
                        }
                    }
                }
            #endif
            }
    }

    // MARK: - Setup
        
    private func setUpQuickActions() {
        let playShortcut = UIApplicationShortcutItem(
            type: "org.wxyc.iphoneapp.play",
            localizedTitle: RadioStation.WXYC.name,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(type: .play),
            userInfo: ["origin": "home screen quick action" as NSString]
        )
        UIApplication.shared.shortcutItems = [playShortcut]
    }
        
    private func handleURL(_ url: URL) {
        // Handle deep links and user activities
        if url.scheme == "wxyc" || url.absoluteString.contains("org.wxyc.iphoneapp.play") {
            AudioPlayerController.shared.play(reason: .deepLink)
        }
    }
        
    private func handleUserActivity(_ userActivity: NSUserActivity) {
        if userActivity.activityType == "org.wxyc.iphoneapp.play" {
            AudioPlayerController.shared.play(reason: .quickAction)
        } else if let intent = userActivity.interaction?.intent as? INPlayMediaIntent {
            AudioPlayerController.shared.play(reason: .siriIntent)
            StructuredPostHogAnalytics.shared.capture(HandleINIntent(
                intentData: intent.description
            ))
        }
    }
        
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
            scheduleBackgroundRefresh()
            // Refresh playlist if cache has expired while in background.
            // This ensures users see fresh data when returning to the app after
            // an extended period, rather than waiting for the next fetch cycle.
            refreshPlaylistIfCacheExpired()
            // Check if user requested cache clear from Settings app
            handleSettingsBundleCacheClear()

        @unknown default:
            break
        }
    }

    private func setUpAnalytics() {
        let config = PostHogConfig(
            apiKey: Secrets.posthogApiKey,
            host: "https://us.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["Build Configuration": buildConfiguration()])
    }
    
    private func setUpQualityAnalytics() {
        AdaptiveQualityController.shared.setAnalytics(StructuredPostHogAnalytics.shared)
    }

    private func setUpThemePickerAnalytics() {
        appState.themePickerState.setAnalytics(StructuredPostHogAnalytics.shared)
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
    
    // MARK: - Background Refresh
    
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.wxyc.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
    
        do {
            try BGTaskScheduler.shared.submit(request)
            Log(.info, category: .general, "Scheduled background refresh for 15 minutes from now")
        } catch {
            Log(.error, category: .general, "Failed to schedule background refresh: \(error)")
            PostHogSDK.shared.capture(error: error, context: "scheduleBackgroundRefresh")
        }
    }
    
    /// Refresh the playlist if the cache has expired.
    /// Called when the app returns to foreground after potentially being backgrounded
    /// for an extended period. This ensures users see fresh data immediately rather
    /// than waiting for the next periodic fetch cycle.
    private func refreshPlaylistIfCacheExpired() {
        Task {
            let isExpired = await appState.playlistService.isCacheExpired()
            if isExpired {
                Log(.info, category: .general, "Cache expired while backgrounded - triggering foreground refresh")
                _ = await appState.playlistService.fetchAndCachePlaylist()
            }
        }
    }

    /// Checks if the user enabled the "Clear Artwork Cache" toggle in Settings.
    /// If enabled, clears the cache and resets the toggle.
    private func handleSettingsBundleCacheClear() {
        guard UserDefaults.standard.bool(forKey: SettingsBundleKeys.clearArtworkCache) else {
            return
        }

        Task {
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

    // MARK: - Wallpaper Palette Extraction

    /// Extracts dominant colors from the current wallpaper and caches the mesh gradient palette.
    /// Called when the theme picker exits after a theme selection, or on first launch.
    private func extractWallpaperPalette() {
        Task {
            // Retry up to 5 times with increasing delays to handle renderer initialization timing
            for attempt in 1...5 {
                let delay = 200 * attempt  // 200ms, 400ms, 600ms, 800ms, 1000ms
                try? await Task.sleep(for: .milliseconds(delay))

                if let snapshot = MetalWallpaperRenderer.captureMainSnapshot() {
                    appState.themeConfiguration.extractAndCachePalette(from: snapshot)
                    Log(.info, category: .general, "Extracted wallpaper palette for theme: \(appState.themeConfiguration.selectedThemeID) (attempt \(attempt))")
                    return
                }
            }
            Log(.warning, category: .general, "Failed to capture wallpaper snapshot after 5 attempts")
        }
    }

    // MARK: - Theme Picker Keyboard Navigation

    /// Toggle theme picker mode on/off.
    private func toggleThemePicker() {
        withAnimation(ThemePickerState.transitionAnimation) {
            if appState.themePickerState.isActive {
                // Exit: confirm selection and close
                appState.themePickerState.confirmSelection(to: appState.themeConfiguration)
                appState.themePickerState.exit()
            } else {
                // Enter: open picker at current theme
                appState.themePickerState.enter(currentThemeID: appState.themeConfiguration.selectedThemeID)
            }
        }
    }

    /// Navigate to the previous theme in the carousel.
    private func navigateToPreviousTheme() {
        let themes = ThemeRegistry.shared.themes
        guard themes.count > 1, appState.themePickerState.isActive else { return }

        withAnimation(.spring(duration: 0.3)) {
            let newIndex = max(0, appState.themePickerState.carouselIndex - 1)
            appState.themePickerState.carouselIndex = newIndex
            appState.themePickerState.updateCenteredTheme(forIndex: newIndex)
        }
    }

    /// Navigate to the next theme in the carousel.
    private func navigateToNextTheme() {
        let themes = ThemeRegistry.shared.themes
        guard themes.count > 1, appState.themePickerState.isActive else { return }

        withAnimation(.spring(duration: 0.3)) {
            let newIndex = min(themes.count - 1, appState.themePickerState.carouselIndex + 1)
            appState.themePickerState.carouselIndex = newIndex
            appState.themePickerState.updateCenteredTheme(forIndex: newIndex)
        }
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
                Log(.error, category: .general, "Failed to donate Siri intent: \(error)")
                PostHogSDK.shared.capture(error: error, context: "WXYCApp: Failed to donate Siri intent")
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
