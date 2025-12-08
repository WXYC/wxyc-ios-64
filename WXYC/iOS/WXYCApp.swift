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
import Playlist
import Core
import Intents
import Logger
import OpenNSFW
import Playback
import PlayerHeaderView
import Playlist
import PostHog
import Secrets
import SwiftUI
import WidgetKit
import WXUI


// Shared app state for cross-scene access (main UI and CarPlay)
@MainActor
class Singletonia: ObservableObject {
    static let shared = Singletonia()

    var nowPlayingInfoCenterManager: NowPlayingInfoCenterManager?
    let playlistService = PlaylistService()
    let artworkService = MultisourceArtworkService()
    
    private var playlistObservationTask: Task<Void, Never>?
    private var isForegrounded = false

    private init() {}
    
    /// Update the foreground state (called when scene phase changes)
    func setForegrounded(_ foregrounded: Bool) {
        isForegrounded = foregrounded
    }
    
    /// Start observing playlist updates and reload widgets when the playlist changes
    /// Note: Widget reloads only occur when the app is in the foreground to avoid
    /// consuming the daily refresh budget (40-70 updates/day) when backgrounded.
    func startObservingPlaylistUpdates() {
        // Cancel any existing observation task
        playlistObservationTask?.cancel()
        
        let service = playlistService
        playlistObservationTask = Task { [weak self] in
            for await _ in service.updates() {
                // Only reload widgets when app is in foreground
                // (foreground reloads don't count against daily budget)
                await MainActor.run {
                    guard let self, self.isForegrounded else { return }
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
    
    deinit {
        playlistObservationTask?.cancel()
    }
}

@main
struct WXYCApp: App {
    @StateObject private var appState = Singletonia.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Cache migration - purge if version changed
        CacheMigrationManager.migrateIfNeeded()
        
        // Seed OpenNSFW model to shared container for widget
        if let bundleURL = Bundle.main.url(forResource: "OpenNSFW", withExtension: "mlmodelc") {
            ModelSeeder.seedIfNeeded(bundleModelURL: bundleURL)
        }
        
        UserDefaults.standard.removeObject(forKey: "isPlaying")
        // Analytics setup
        setUpAnalytics()
        PostHogSDK.shared.capture("app launch")

        // Configure shared AudioPlayerController with StreamingAudioPlayer
        AudioPlayerController.shared.defaultStreamURL = RadioStation.WXYC.streamURL

        // AVAudioSession setup
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playback, mode: .default, policy: .longFormAudio)
        } catch {
            Log(.error, "Could not set AVAudioSession category: \(error)")
            PostHogSDK.shared.capture(error: error, context: "WXYCApp: Could not set AVAudioSession category")
        }

        // UIKit appearance setup
        #if os(iOS)
        UINavigationBar.appearance().barStyle = .black
        #endif

        // Widget reload
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case let .success(configurations) = result else {
                return
            }

            for configuration in configurations {
                Log(.info, configuration)
            }

            WidgetCenter.shared.reloadAllTimelines()
        }

        // Siri intent donation
        Self.donateSiriIntent()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Rectangle()
                    .fill(WXYCBackground())
                    .ignoresSafeArea()

                RootTabView()
                    .frame(maxWidth: 440)
                    .background(WXYCBackground())
                    .environmentObject(appState)
                    .environment(\.playlistService, appState.playlistService)
                    .environment(\.artworkService, appState.artworkService)
                    .environment(\.playbackController, AudioPlayerController.shared)
                    .onAppear {
                        setUpNowPlayingInfoCenter()
                        setUpQuickActions()
                        appState.setForegrounded(true)
                        appState.startObservingPlaylistUpdates()
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
                    .safeAreaPadding([.top, .bottom])
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .backgroundTask(.appRefresh("com.wxyc.refresh")) {
            Log(.info, "Background refresh started")
            
            // Fetch fresh playlist (this always fetches from network, ignoring cache)
            // and caches it with a 15-minute lifespan
            let playlist = await appState.playlistService.fetchAndCachePlaylist()
            
            // Update widget with fresh data
            WidgetCenter.shared.reloadAllTimelines()
            
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
                            WidgetCenter.shared.reloadAllTimelines()
                            Log(.info, "Manual background refresh completed with \(playlist.entries.count) entries")
                        }
                    }
                }
            #endif
            }
    }

    // MARK: - Setup

    private func setUpNowPlayingInfoCenter() {
        let nowPlayingService = NowPlayingService(
            playlistService: appState.playlistService,
            artworkService: appState.artworkService
        )
        appState.nowPlayingInfoCenterManager = NowPlayingInfoCenterManager(
            nowPlayingService: nowPlayingService
        )
    }

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
            // Save state and handle audio session when entering background
            PostHogSDK.shared.capture("App entered background", properties: [
                "Is Playing?": AudioPlayerController.shared.isPlaying
            ])
            UserDefaults.wxyc.set(AudioPlayerController.shared.isPlaying, forKey: "isPlaying")
            AudioPlayerController.shared.handleAppDidEnterBackground()
            appState.setForegrounded(false)

        case .inactive:
            // Handle becoming inactive (e.g., phone call, control center)
            appState.setForegrounded(false)

        case .active:
            // Handle becoming active - reactivate audio session if needed
            AudioPlayerController.shared.handleAppWillEnterForeground()
            appState.setForegrounded(true)
            // Reload widgets when app becomes active to show latest data
            WidgetCenter.shared.reloadAllTimelines()
            // Schedule next background refresh
            scheduleBackgroundRefresh()

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
    ZStack {
        Rectangle()
            .fill(WXYCBackground())
            .ignoresSafeArea()
        
        RootTabView()
            .environment(\.playlistService, PlaylistService())
            .environment(\.artworkService, MultisourceArtworkService())
            .environment(\.playbackController, AudioPlayerController.shared)
            .preferredColorScheme(.light)
    }
}
