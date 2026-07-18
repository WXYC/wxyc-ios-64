//
//  RootTabView.swift
//  WXYC
//
//  Root tab navigation for iOS app.
//
//  Created by Jake Bromberg on 11/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playlist
import Wallpaper
import WXUI

struct RootTabView: View {
    enum Page: CaseIterable {
        case playlist
        case onTour
        case infoDetail

        /// Tab label. Also the accessibility label the tab bar exposes.
        var title: String {
            switch self {
            case .playlist: "Now Playing"
            case .onTour: "On Tour"
            case .infoDetail: "Info"
            }
        }

        /// SF Symbol for the tab glyph. `radio` matches the widget and Siri
        /// intent; `info.circle` matches the playcut-detail row — iconography
        /// the app already speaks on adjacent surfaces. `ticket` matches the Box
        /// Office ticket language the On Tour surface reuses.
        var systemImage: String {
            switch self {
            case .playlist: "radio"
            case .onTour: "ticket"
            case .infoDetail: "info.circle"
            }
        }

        /// Stable identifier for UI tests to select the tab item, independent of
        /// the localized title or the tab bar's element type.
        var accessibilityIdentifier: String {
            switch self {
            case .playlist: "tab.nowPlaying"
            case .onTour: "tab.onTour"
            case .infoDetail: "tab.info"
            }
        }
    }

    @State private var selectedPage = Page.playlist
    @State private var selectedPlaycut: PlaycutSelection?

    @Environment(Singletonia.self) private var appState
    @Environment(\.themeAppearance) private var appearance

    var body: some View {
        TabView(selection: $selectedPage) {
            Tab(Page.playlist.title, systemImage: Page.playlist.systemImage, value: Page.playlist) {
                PlaylistView(selectedPlaycut: $selectedPlaycut)
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.playlist.accessibilityIdentifier)

            Tab(Page.onTour.title, systemImage: Page.onTour.systemImage, value: Page.onTour) {
                OnTourTabView()
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.onTour.accessibilityIdentifier)

            Tab(Page.infoDetail.title, systemImage: Page.infoDetail.systemImage, value: Page.infoDetail) {
                InfoDetailView()
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.infoDetail.accessibilityIdentifier)
        }
        // Selected tab item picks up the theme's accent color rather than the
        // system default tint.
        .tint(appearance.accentColor.color(brightness: appearance.accentColor.brightness))
        .overlaySheet(isPresented: Binding(
            get: { selectedPlaycut != nil },
            set: { if !$0 { selectedPlaycut = nil } }
        )) {
            if let selection = selectedPlaycut {
                PlaycutDetailView(playcut: selection.playcut, artwork: selection.artwork)
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.playlistService, PlaylistService())
}
