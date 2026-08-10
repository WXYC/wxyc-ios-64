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

import Core
import Logger
import Playback
import SwiftUI
import Wallpaper

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
            .onContinueUserActivity(WXYCUserActivity.play) { userActivity in
                handleUserActivity(userActivity)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                handleUserActivity(userActivity)
            }
    }

    // MARK: - Appearance

    private func handleAppear() {
        setUpQuickActions()
        appState.startWidgetStateService()
        appState.startReviewRequestTracking()
        // Register the shared-show-link observer here, synchronously and before
        // the launch link is delivered, so a cold launch into a `wxyc.org/shows/…`
        // link can't post the message before anyone is listening (#537).
        appState.startObservingConcertOpen()
        // Same reasoning for a cold launch straight into a Spotlight/Siri
        // playcut result or a `wxyc://playcut/<id>` link (#434).
        appState.startObservingPlaycutOpen()
        // Same reasoning for a cold launch straight into a Spotlight/Siri
        // `OpenVenue` result (OT-C4).
        appState.startObservingVenueOpen()

        // First-launch path: the wallpaper isn't cached yet, so prime the
        // mesh-gradient palette before the user sees the home screen.
        if appState.themeConfiguration.meshGradientPalette == nil {
            WallpaperPaletteExtraction.extract(into: appState.themeConfiguration)
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
                playlistService: appState.playlistService,
                appState: appState
            )
        }
    }

    private func setUpQuickActions() {
        let playShortcut = UIApplicationShortcutItem(
            type: WXYCUserActivity.play,
            localizedTitle: RadioStation.WXYC.name,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(type: .play),
            userInfo: ["origin": "home screen quick action" as NSString]
        )
        UIApplication.shared.shortcutItems = [playShortcut]
    }

    // MARK: - Deep links and Siri

    private func handleURL(_ url: URL) {
        DeepLinkHandler.handle(url: url)
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        DeepLinkHandler.handle(userActivity: userActivity)
    }

    // MARK: - Memory

    private func handleMemoryWarning() {
        Log(.warning, category: .general, "Memory warning received — releasing caches and textures")
        Task {
            await appState.artworkService.releaseMemory()
        }
    }
}
