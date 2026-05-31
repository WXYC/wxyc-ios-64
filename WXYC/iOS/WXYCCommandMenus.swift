//
//  WXYCCommandMenus.swift
//  WXYC
//
//  Command menus for the iOS / Mac Catalyst app: Playback (Space to play/pause),
//  Themes (Return / arrows for picker), and a Debug menu in non-release builds.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Logger
import Playback
import SwiftUI
import Wallpaper

/// `Commands` body extracted from `WXYCApp` so the App struct stays a thin
/// wiring layer over composition units.
struct WXYCCommandMenus: Commands {
    let appState: Singletonia

    var body: some Commands {
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
            // Hits the network unconditionally and does NOT reschedule the next refresh —
            // routing through BackgroundRefreshController would conflate developer trigger
            // with the iOS-scheduled refresh and log under the wrong message.
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
