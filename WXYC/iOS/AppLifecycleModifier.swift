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
        // Register the shared-show-link observer here, synchronously and before
        // the launch link is delivered, so a cold launch into a `wxyc.org/shows/…`
        // link can't post the message before anyone is listening (#537).
        appState.startObservingConcertOpen()
        // Same reasoning for a cold launch straight into a Spotlight/Siri
        // playcut result or a `wxyc://playcut/<id>` link (#434).
        appState.startObservingPlaycutOpen()

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
                playlistService: appState.playlistService,
                appState: appState
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
        // `onOpenURL` delivers both `wxyc://` scheme links (Spotlight, shortcuts)
        // and the https universal link handed over as a Smart App Banner's
        // `app-argument` — which arrives here rather than as an `NSUserActivity`.
        // `WXYCDeepLink(routing:)` resolves either spelling. A universal link
        // that is *tapped* as a web link still comes through `handleUserActivity`.
        switch WXYCDeepLink(routing: url) {
        case .playcut(let id):
            NotificationCenter.default.post(PlaycutOpenMessage(playcutID: id), subject: nil)
        case .concert(let id):
            NotificationCenter.default.post(
                ConcertOpenMessage(concertID: id, source: .scheme),
                subject: nil
            )
        case .play:
            AudioPlayerController.shared.play(reason: .deepLink)
        case nil:
            // Unrecognised URL — the `.onContinueUserActivity` handler (line 40)
            // owns the legacy `org.wxyc.iphoneapp.play` activity, not this path.
            break
        }
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            // A tapped universal link (`https://wxyc.org/shows/<id>`). Route
            // recognised show links to the On Tour tab; ignore any other web URL
            // the AASA might hand us so it falls through to Safari.
            if let webpageURL = userActivity.webpageURL,
               case .concert(let id)? = WXYCDeepLink(universalLink: webpageURL) {
                NotificationCenter.default.post(
                    ConcertOpenMessage(concertID: id, source: .universalLink),
                    subject: nil
                )
            }
        } else if userActivity.activityType == "org.wxyc.iphoneapp.play" {
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
