//
//  AppLifecycleModifier.swift
//  WXYC
//
//  Bundles the per-window lifecycle hooks for the iOS app: scene-phase handling,
//  memory-warning response, deep-link / user-activity routing, review-request
//  observation, theme-picker exit, quick-actions registration, marketing mode,
//  Settings-bundle cache clear, and wallpaper palette extraction.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Caching
import Core
import Intents
import Logger
import Playback
import StoreKit
import SwiftUI
import Wallpaper

private enum SettingsBundleKeys {
    static let clearArtworkCache = "clear_artwork_cache"
}

/// Lifecycle modifier extracted from `WXYCApp.body`. Owns the per-window state
/// (foreground refresh + cache cleanup tasks) and routes every observable
/// transition through a small set of named handlers.
struct AppLifecycleModifier: ViewModifier {
    let appState: Singletonia

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    @State private var foregroundRefreshTask: Task<Void, Never>?
    @State private var cacheCleanupTask: Task<Void, Never>?

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
                if wasActive && !isActive {
                    extractWallpaperPalette()
                }
            }
    }

    // MARK: - Appearance

    private func handleAppear() {
        setUpQuickActions()
        appState.setForegrounded(true)
        appState.startWidgetStateService()
        appState.startReviewRequestTracking()

        if appState.themeConfiguration.meshGradientPalette == nil {
            extractWallpaperPalette()
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

    // MARK: - Memory

    private func handleMemoryWarning() {
        Log(.warning, category: .general, "Memory warning received — releasing caches and textures")
        Task {
            await appState.artworkService.releaseMemory()
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
            foregroundRefreshTask = refreshPlaylistIfCacheExpired()
            cacheCleanupTask = handleSettingsBundleCacheClear()

        @unknown default:
            break
        }
    }

    @discardableResult
    private func refreshPlaylistIfCacheExpired() -> Task<Void, Never> {
        Task {
            let isExpired = await appState.playlistService.isCacheExpired()
            if isExpired {
                Log(.info, category: .general, "Cache expired while backgrounded - triggering foreground refresh")
                _ = await appState.playlistService.fetchAndCachePlaylist()
            }
        }
    }

    @discardableResult
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

    // MARK: - Wallpaper palette

    /// Captures the current wallpaper snapshot and caches its mesh-gradient palette.
    /// Retries up to 5× with increasing delays to absorb renderer init timing.
    private func extractWallpaperPalette() {
        Task {
            for attempt in 1...5 {
                let delay = 200 * attempt
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
}
