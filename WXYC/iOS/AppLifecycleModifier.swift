//
//  AppLifecycleModifier.swift
//  WXYC
//
//  Bundles the per-window (View-level) lifecycle hooks for the iOS app:
//  memory-warning response, deep-link / user-activity routing, .onAppear
//  bootstrap (quick actions, marketing mode, first-launch palette). Scene-level
//  observation (scenePhase, review-request, picker-exit) and the @State that
//  tracks foreground/cleanup Tasks stay in `WXYCApp` so multi-window Catalyst
//  doesn't fire them per window.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Core
import Intents
import Logger
import Playback
import SwiftUI
import Wallpaper
import WXYCIntents

/// View-level lifecycle modifier extracted from `WXYCApp.body`. Routes
/// per-window observations through a small set of named handlers.
struct AppLifecycleModifier: ViewModifier {
    let appState: Singletonia

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                handleMemoryWarning()
            }
            .onAppear {
                handleAppear()
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
    }

    // MARK: - Appearance

    private func handleAppear() {
        setUpQuickActions()
        appState.setForegrounded(true)
        appState.startWidgetStateService()
        appState.startReviewRequestTracking()

        // First-launch path: the wallpaper isn't cached yet, so prime the
        // mesh-gradient palette before the user sees the home screen.
        if appState.themeConfiguration.meshGradientPalette == nil {
            Self.extractWallpaperPalette(into: appState.themeConfiguration)
        }

        #if os(iOS)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
        #endif

        if MarketingModeController.isEnabled {
            MarketingModeController().start(
                playbackController: AudioPlayerController.shared,
                pickerState: appState.themePickerState,
                configuration: appState.themeConfiguration,
                playlistService: appState.playlistService
            )
        }
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

    // MARK: - Deep links and Siri

    private func handleURL(_ url: URL) {
        switch WXYCDeepLink(url: url) {
        case .playcut(let id):
            NotificationCenter.default.post(PlaycutOpenMessage(playcutID: id), subject: nil)
        case .play:
            AudioPlayerController.shared.play(reason: .deepLink)
        case nil:
            // Legacy Siri user-activity URL — preserved because the shortcut
            // item at line 82 still emits this activity type.
            if url.absoluteString.contains("org.wxyc.iphoneapp.play") {
                AudioPlayerController.shared.play(reason: .deepLink)
            }
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

    // MARK: - Memory

    private func handleMemoryWarning() {
        Log(.warning, category: .general, "Memory warning received — releasing caches and textures")
        Task {
            await appState.artworkService.releaseMemory()
        }
    }

    // MARK: - Wallpaper palette

    /// Captures the current wallpaper snapshot and caches its mesh-gradient
    /// palette into `themeConfiguration`. Retries up to 5× (200, 400, 600, 800,
    /// 1000 ms) to absorb renderer init timing.
    ///
    /// Exposed as a static func so both the View-level `.onAppear` (first
    /// launch) and the Scene-level `.onChange(of: themePickerState.isActive)`
    /// in `WXYCApp` can share the same implementation.
    static func extractWallpaperPalette(into themeConfiguration: ThemeConfiguration) {
        Task {
            for attempt in 1...5 {
                let delay = 200 * attempt
                try? await Task.sleep(for: .milliseconds(delay))

                if let snapshot = MetalWallpaperRenderer.captureMainSnapshot() {
                    themeConfiguration.extractAndCachePalette(from: snapshot)
                    Log(.info, category: .general, "Extracted wallpaper palette for theme: \(themeConfiguration.selectedThemeID) (attempt \(attempt))")
                    return
                }
            }
            Log(.warning, category: .general, "Failed to capture wallpaper snapshot after 5 attempts")
        }
    }
}
