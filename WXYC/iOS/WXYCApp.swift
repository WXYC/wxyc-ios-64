//
//  WXYCApp.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppServices
import Artwork
import AVFoundation
import BackgroundTasks
import Caching
import Core
import Intents
import Logger
import Observation
import OpenNSFW
import Playback
import PlayerHeaderView
import Playlist
import PostHog
import Secrets
import SwiftUI
import Wallpaper
import WXUI
#if DEBUG
import DebugPanel
#endif


// Shared app state for cross-scene access (main UI and CarPlay)
@MainActor
@Observable
final class Singletonia {
    static let shared = Singletonia()

    let nowPlayingInfoCenterManager: NowPlayingInfoCenterManager
    let playlistService = PlaylistService()
    let artworkService = MultisourceArtworkService()
    let widgetStateService: WidgetStateService

    let themeConfiguration = ThemeConfiguration()
    let themePickerState = ThemePickerState()

    private init() {
        self.widgetStateService = WidgetStateService(
            playbackController: AudioPlayerController.shared,
            playlistService: playlistService
        )
    
        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: artworkService
        )
        nowPlayingInfoCenterManager = NowPlayingInfoCenterManager(nowPlayingService: nowPlayingService)
    }

    /// Update the foreground state (called when scene phase changes)
    func setForegrounded(_ foregrounded: Bool) {
        widgetStateService.setForegrounded(foregrounded)
    }
        
    /// Start the widget state service to observe playback and playlist updates
    func startWidgetStateService() {
        widgetStateService.start()
    }
}

@main
struct WXYCApp: App {
    @State private var appState = Singletonia.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Cache migration - purge if version changed
        CacheMigrationManager.migrateIfNeeded()
        
        // Seed OpenNSFW model to shared container for widget
        if let bundleURL = Bundle.main.url(forResource: "OpenNSFW", withExtension: "mlmodelc") {
            ModelSeeder.seedIfNeeded(bundleModelURL: bundleURL)
        }
        
        // Enable battery monitoring for thermal context
        ThermalContext.enableBatteryMonitoring()

        // Analytics setup
        setUpAnalytics()
        PostHogSDK.shared.capture("app launch")

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
                        .forceLightStatusBar()
                        .onAppear {
                            setUpQuickActions()
                            appState.setForegrounded(true)
                            appState.startWidgetStateService()

                            // Force status bar to be light
#if os(iOS)
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first {
                                window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
                            }
#endif
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
        .backgroundTask(.appRefresh("com.wxyc.refresh")) {
            Log(.info, "Background refresh started")

            // Fetch fresh playlist (this always fetches from network, ignoring cache)
            // and caches it with a 15-minute lifespan.
            // Note: Widget reload is handled by WidgetStateService observing playlist updates.
            let playlist = await appState.playlistService.fetchAndCachePlaylist()

            Log(.info, "Background refresh completed successfully with \(playlist.entries.count) entries")

            PostHogSDK.shared.capture("Background refresh completed", additionalData: [
                "entry_count": "\(playlist.entries.count)"
            ])

            // Schedule the next refresh
            await MainActor.run {
                scheduleBackgroundRefresh()
            }
        }
        .commands {
                CommandMenu("Playback") {
                    Button("Play/Pause") {
                        AudioPlayerController.shared.toggle()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                }
            #if DEBUG
                CommandMenu("Debug") {
                    Button("Trigger Background Refresh") {
                        Task {
                            Log(.info, "Manual background refresh triggered")
                            let playlist = await appState.playlistService.fetchAndCachePlaylist()
                            Log(.info, "Manual background refresh completed with \(playlist.entries.count) entries")
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
            AudioPlayerController.shared.play()
        }
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        if userActivity.activityType == "org.wxyc.iphoneapp.play" {
            AudioPlayerController.shared.play()
        } else if let intent = userActivity.interaction?.intent as? INPlayMediaIntent {
            AudioPlayerController.shared.play()
            PostHogSDK.shared.capture(
                "Handle INIntent",
                context: "Intents",
                additionalData: ["intent data": intent.description]
            )
        }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            PostHogSDK.shared.capture("App entered background", properties: [
                "Is Playing?": AudioPlayerController.shared.isPlaying
            ])
            AudioPlayerController.shared.handleAppDidEnterBackground()
            AdaptiveThermalController.shared.handleBackgrounded()
            appState.setForegrounded(false)

        case .inactive:
            appState.setForegrounded(false)

        case .active:
            AudioPlayerController.shared.handleAppWillEnterForeground()
            AdaptiveThermalController.shared.handleForegrounded()
            appState.setForegrounded(true)
            scheduleBackgroundRefresh()
            // Refresh playlist if cache has expired while in background.
            // This ensures users see fresh data when returning to the app after
            // an extended period, rather than waiting for the next fetch cycle.
            refreshPlaylistIfCacheExpired()

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
            Log(.info, "Scheduled background refresh for 15 minutes from now")
        } catch {
            Log(.error, "Failed to schedule background refresh: \(error)")
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
                Log(.info, "Cache expired while backgrounded - triggering foreground refresh")
                _ = await appState.playlistService.fetchAndCachePlaylist()
            }
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

                PostHogSDK.shared.capture(
                    "Intents",
                    context: "donateSiriIntent",
                    additionalData: [
                        "intent data": activity.description
                    ]
                )
            } catch {
                Log(.error, "Failed to donate Siri intent: \(error)")
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
            .environment(\.playlistService, PlaylistService())
            .environment(\.artworkService, MultisourceArtworkService())
            .environment(\.playbackController, AudioPlayerController.shared)
            .preferredColorScheme(.light)
    }
}
