//
//  WXYCApp.swift
//  WXYC
//
//  SwiftUI App replacing AppDelegate
//

import SwiftUI
import Core
import Logger
import PostHog
import Secrets
import WidgetKit
import Intents
import AVFoundation

// Shared RadioPlayerController singleton for app-wide access
@MainActor
public class AppState: ObservableObject {
    static let shared = AppState()

    var nowPlayingInfoCenterManager: NowPlayingInfoCenterManager?

    private init() {}
}

@main
struct WXYCApp: App {
    @StateObject private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UserDefaults.standard.removeObject(forKey: "isPlaying")
        // Analytics setup
        setUpAnalytics()
        PostHogSDK.shared.capture("app launch")

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
            RootTabView()
                .environmentObject(appState)
                .environment(\.radioPlayerController, RadioPlayerController.shared)
                .onAppear {
                    setUpNowPlayingInfoCenter()
                    setUpQuickActions()
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
//                .ignoresSafeArea()
                .safeAreaPadding([.top, .bottom])
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .backgroundTask(.appRefresh("com.wxyc.refresh")) { _ in
            // Handle background refresh if needed
        }
    }

    // MARK: - Setup

    private func setUpNowPlayingInfoCenter() {
        let nowPlayingService = NowPlayingService(
            playlistService: PlaylistService(),
            artworkService: MultisourceArtworkService()
        )
        appState.nowPlayingInfoCenterManager = NowPlayingInfoCenterManager(
            nowPlayingService: nowPlayingService,
            radioPlayerController: RadioPlayerController.shared
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
            try? RadioPlayerController.shared.play(reason: "URL scheme")
        }
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        if userActivity.activityType == "org.wxyc.iphoneapp.play" {
            try? RadioPlayerController.shared.play(reason: "Siri suggestion (NSUserActivity)")
        } else if let intent = userActivity.interaction?.intent as? INPlayMediaIntent {
            try? RadioPlayerController.shared.play(reason: "Siri suggestion (INPlayMediaIntent)")
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
            // Save state when entering background
            PostHogSDK.shared.capture("App entered background", properties: [
                "Is Playing?": RadioPlayerController.shared.isPlaying
            ])
            UserDefaults.wxyc.set(RadioPlayerController.shared.isPlaying, forKey: "isPlaying")

        case .inactive:
            // Handle becoming inactive (e.g., phone call, control center)
            break

        case .active:
            // Handle becoming active
            break

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
    RootTabView()
}
