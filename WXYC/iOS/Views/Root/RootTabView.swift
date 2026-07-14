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
import WXUI

struct RootTabView: View {
    enum Page: CaseIterable {
        case playlist
        case touring
        case infoDetail

        /// Tab label. Also the accessibility label the tab bar exposes.
        var title: String {
            switch self {
            case .playlist: "Now Playing"
            case .touring: "On Tour"
            case .infoDetail: "Info"
            }
        }

        /// SF Symbol for the tab glyph. `radio` matches the widget and Siri
        /// intent; `info.circle` matches the playcut-detail row — iconography
        /// the app already speaks on adjacent surfaces. `ticket` matches the Box
        /// Office ticket language the Touring surface reuses.
        var systemImage: String {
            switch self {
            case .playlist: "radio"
            case .touring: "ticket"
            case .infoDetail: "info.circle"
            }
        }

        /// Stable identifier for UI tests to select the tab item, independent of
        /// the localized title or the tab bar's element type.
        var accessibilityIdentifier: String {
            switch self {
            case .playlist: "tab.nowPlaying"
            case .touring: "tab.touring"
            case .infoDetail: "tab.info"
            }
        }
    }

    @State private var selectedPage = Page.playlist
    @State private var selectedPlaycut: PlaycutSelection?

    var body: some View {
        TabView(selection: $selectedPage) {
            Tab(Page.playlist.title, systemImage: Page.playlist.systemImage, value: Page.playlist) {
                PlaylistView(selectedPlaycut: $selectedPlaycut)
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.playlist.accessibilityIdentifier)

            Tab(Page.touring.title, systemImage: Page.touring.systemImage, value: Page.touring) {
                TouringTabView()
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.touring.accessibilityIdentifier)

            Tab(Page.infoDetail.title, systemImage: Page.infoDetail.systemImage, value: Page.infoDetail) {
                InfoDetailView()
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.infoDetail.accessibilityIdentifier)
        }
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
