//
//  WXYCMacApp.swift
//  WXYC
//
//  Main entry point for the native macOS app. Initializes analytics, error
//  reporting, and shared services, then presents a NavigationSplitView with
//  the playlist sidebar and track detail pane.
//
//  Created by Jake Bromberg on 03/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Artwork
import Caching
import Core
import Logger
import Observation
import Playback
import Playlist
import PostHog
import Secrets
import Sentry
import SwiftUI
import Wallpaper
import WXUI

@main
struct WXYCMacApp: App {
    @State private var appState = MacSingletonia.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CacheMigrationManager.migrateIfNeeded()

        #if DEBUG
        Task {
            await CacheCoordinator.migratePngCacheToHeif()
        }
        #endif

        DeviceContext.enableBatteryMonitoring()

        setUpAnalytics()
        setUpSentry()
        setUpErrorReporting()
        setUpQualityAnalytics()
        setUpThemePickerAnalytics()
        StructuredPostHogAnalytics.shared.capture(AppLaunch(
            hasUsedThemePicker: appState.themePickerState.persistence.hasEverUsedPicker,
            buildType: buildConfiguration()
        ))
    }

    var body: some Scene {
        WindowGroup {
            ThemePickerContainer(
                configuration: appState.themeConfiguration,
                pickerState: appState.themePickerState
            ) {
                MacRootView()
                    .environment(appState)
                    .environment(\.playlistService, appState.playlistService)
                    .environment(\.artworkService, appState.artworkService)
                    .environment(\.playbackController, AudioPlayerController.shared)
                    .onAppear {
                        if appState.themeConfiguration.meshGradientPalette == nil {
                            extractWallpaperPalette()
                        }
                    }
                    .onOpenURL { url in
                        handleURL(url)
                    }
            }
        }
        .defaultSize(width: 420, height: 750)
        .windowResizability(.contentMinSize)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: appState.themePickerState.isActive) { wasActive, isActive in
            if wasActive && !isActive {
                extractWallpaperPalette()
            }
        }
        .commands {
            CommandMenu("Playback") {
                Button("Play/Pause") {
                    AudioPlayerController.shared.toggle(reason: .remoteToggleCommand)
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
            #if DEBUG
            CommandMenu("Debug") {
                Button("Trigger Playlist Refresh") {
                    Task {
                        Log(.info, category: .general, "Manual playlist refresh triggered")
                        let playlist = await appState.playlistService.fetchAndCachePlaylist()
                        Log(.info, category: .general, "Manual playlist refresh completed with \(playlist.entries.count) entries")
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Setup

    private func setUpAnalytics() {
        let config = PostHogConfig(
            apiKey: Secrets.posthogApiKey,
            host: "https://us.i.posthog.com"
        )
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["Build Configuration": buildConfiguration()])
    }

    private func setUpSentry() {
        SentrySDK.start { options in
            options.dsn = Secrets.sentryDsn
            options.enableAutoSessionTracking = true
            options.tracesSampleRate = 0.1
            options.enableNetworkTracking = true
            options.enableFileIOTracing = true
            options.enableSwizzling = true
            #if DEBUG
            options.debug = true
            #endif
        }
    }

    private func setUpErrorReporting() {
        ErrorReporting.shared = CompositeErrorReporter()
        Logger.addDestination(SentryBreadcrumbDestination())
    }

    private func setUpQualityAnalytics() {
        AdaptiveQualityController.shared.setAnalytics(StructuredPostHogAnalytics.shared)
    }

    private func setUpThemePickerAnalytics() {
        appState.themePickerState.setAnalytics(StructuredPostHogAnalytics.shared)
    }

    private func buildConfiguration() -> String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    // MARK: - Event Handling

    private func handleURL(_ url: URL) {
        if url.scheme == "wxyc" || url.absoluteString.contains("org.wxyc.iphoneapp.play") {
            AudioPlayerController.shared.play(reason: .deepLink)
        }
    }

    private func handleScenePhaseChange(from _: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            StructuredPostHogAnalytics.shared.capture(AppEnteredBackground(
                isPlaying: AudioPlayerController.shared.isPlaying
            ))
            AdaptiveQualityController.shared.handleBackgrounded()

        case .inactive:
            break

        case .active:
            AdaptiveQualityController.shared.handleForegrounded()
            refreshPlaylistIfCacheExpired()

        @unknown default:
            break
        }
    }

    private func refreshPlaylistIfCacheExpired() {
        Task {
            let isExpired = await appState.playlistService.isCacheExpired()
            if isExpired {
                Log(.info, category: .general, "Cache expired while backgrounded - triggering foreground refresh")
                _ = await appState.playlistService.fetchAndCachePlaylist()
            }
        }
    }

    // MARK: - Wallpaper Palette Extraction

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

    // MARK: - Theme Picker Keyboard Navigation

    private func toggleThemePicker() {
        withAnimation(ThemePickerState.transitionAnimation) {
            if appState.themePickerState.isActive {
                appState.themePickerState.confirmSelection(to: appState.themeConfiguration)
                appState.themePickerState.exit()
            } else {
                appState.themePickerState.enter(currentThemeID: appState.themeConfiguration.selectedThemeID)
            }
        }
    }

    private func navigateToPreviousTheme() {
        let themes = ThemeRegistry.shared.themes
        guard themes.count > 1, appState.themePickerState.isActive else { return }

        withAnimation(.spring(duration: 0.3)) {
            let newIndex = max(0, appState.themePickerState.carouselIndex - 1)
            appState.themePickerState.carouselIndex = newIndex
            appState.themePickerState.updateCenteredTheme(forIndex: newIndex)
        }
    }

    private func navigateToNextTheme() {
        let themes = ThemeRegistry.shared.themes
        guard themes.count > 1, appState.themePickerState.isActive else { return }

        withAnimation(.spring(duration: 0.3)) {
            let newIndex = min(themes.count - 1, appState.themePickerState.carouselIndex + 1)
            appState.themePickerState.carouselIndex = newIndex
            appState.themePickerState.updateCenteredTheme(forIndex: newIndex)
        }
    }
}
