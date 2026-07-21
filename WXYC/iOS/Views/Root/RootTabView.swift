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
        case liked
        case station

        /// Tab label. Also the accessibility label the tab bar exposes.
        var title: String {
            switch self {
            case .playlist: "Now Playing"
            case .onTour: "On Tour"
            case .liked: "Liked"
            case .station: "Station"
            }
        }

        /// SF Symbol for the tab glyph — iconography the app already speaks on
        /// adjacent surfaces. `radio` matches the widget and Siri intent;
        /// `ticket` matches the Box Office ticket language the On Tour surface
        /// reuses; `heart` matches the like affordance on playcut rows and the
        /// detail card (#492); `antenna.radiowaves.left.and.right` reads the
        /// Station page as the broadcast itself — the "Info" junk drawer
        /// regrouped into station identity plus the "Talk to the booth" channels.
        var systemImage: String {
            switch self {
            case .playlist: "radio"
            case .onTour: "ticket"
            case .liked: "heart"
            case .station: "antenna.radiowaves.left.and.right"
            }
        }

        /// Stable identifier for UI tests to select the tab item, independent of
        /// the localized title or the tab bar's element type.
        var accessibilityIdentifier: String {
            switch self {
            case .playlist: "tab.nowPlaying"
            case .onTour: "tab.onTour"
            case .liked: "tab.liked"
            case .station: "tab.station"
            }
        }

        /// Maps a `-marketing` recording route to its tab. Total (never fails);
        /// the `.onChange` call site below handles a `nil` route as a no-op, so
        /// this mapper stays pure and directly testable.
        static func page(for route: MarketingRoute) -> Page {
            switch route {
            case .nowPlaying: .playlist
            case .onTour: .onTour
            case .liked: .liked
            case .station: .station
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
                OnTourTabView(model: appState.marketingOnTourModel)
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.onTour.accessibilityIdentifier)

            Tab(Page.liked.title, systemImage: Page.liked.systemImage, value: Page.liked) {
                LikedTabView()
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.liked.accessibilityIdentifier)

            Tab(Page.station.title, systemImage: Page.station.systemImage, value: Page.station) {
                StationView()
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(Page.station.accessibilityIdentifier)
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
        // A shared show link arrived: switch to On Tour so the tab materializes and
        // its resolution ladder (`OnTourTabView`) can open the show. Reacting here —
        // not in `OnTourTabView` — guarantees the tab is built even when it wasn't
        // the visible one. The tab consumes and clears the link once resolved.
        .onChange(of: appState.pendingConcertLink) { _, link in
            if link != nil {
                selectedPage = .onTour
            }
        }
        // A `-marketing` recording drives tab navigation from outside the view,
        // exactly like the shared-show-link case above. Nil is a no-op — it never
        // fires for a production launch (`marketingRoute` stays nil).
        .onChange(of: appState.marketingRoute) { _, route in
            if let route {
                selectedPage = Page.page(for: route)
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.playlistService, PlaylistService())
}
