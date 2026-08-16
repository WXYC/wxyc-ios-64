//
//  WXYCCommandMenus.swift
//  WXYC
//
//  Command menus for the iOS / Mac Catalyst app: Playback (Space to play/pause),
//  Themes (Return / arrows for the picker, j/k to switch outright), and a Debug
//  menu in non-release builds.
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
                cycleTheme(.previous)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!appState.themePickerState.isActive)

            Button("Next Theme") {
                cycleTheme(.next)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!appState.themePickerState.isActive)

            // Same step, always available: with the picker closed these swap the
            // theme outright, so a keyboard user can flip through the set without
            // going through the picker at all.
            Button("Switch to Previous Theme") {
                cycleTheme(.previous)
            }
            .keyboardShortcut("k", modifiers: [])

            Button("Switch to Next Theme") {
                cycleTheme(.next)
            }
            .keyboardShortcut("j", modifiers: [])
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

    private func cycleTheme(_ direction: ThemeCycling.Direction) {
        // Read before the step: a committed switch is exactly the picker-closed case.
        let wasPickerActive = appState.themePickerState.isActive

        guard let destinationID = ThemeCycling.cycle(
            direction,
            configuration: appState.themeConfiguration,
            pickerState: appState.themePickerState
        ) else { return }

        guard !wasPickerActive else { return }

        Log(.info, category: .general, "Theme switched by keyboard to '\(destinationID)'")
        // Mirrors the picker-exit hook in `WXYCApp`: the mesh-gradient palette is
        // cached per theme, and `selectedThemeID`'s `didSet` clears it for any
        // theme that has never been captured.
        WallpaperPaletteExtraction.extract(into: appState.themeConfiguration)
    }
}
