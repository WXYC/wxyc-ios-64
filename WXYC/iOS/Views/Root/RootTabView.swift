//
//  RootTabView.swift
//  WXYC
//
//  Root tab navigation for iOS app.
//
//  Created by Jake Bromberg on 11/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppServices
import SwiftUI
import Playlist
import Wallpaper
import WXUI

struct RootTabView: View {
    @State private var selectedPage = AppSection.playlist
    @State private var selectedPlaycut: PlaycutSelection?
    /// The zoom-transition namespace tying each playcut row to the detail cover
    /// it opens, mirroring `OnTourTabView`'s concert-row → concert-detail zoom.
    @Namespace private var playcutZoom

    @Environment(Singletonia.self) private var appState
    @Environment(\.themeAppearance) private var appearance

    /// LCD active brightness, moved by the theme's accent brightness offset.
    ///
    /// `accentColor` and `lcdAccentColor` differ only by that offset, so a theme with
    /// no offset keeps a tab tint that matches the LCD.
    ///
    /// A negative offset scales the LCD value instead of subtracting from it, so the
    /// tint fades evenly from the LCD brightness toward black. There is no cap at 1,
    /// because a cap would jump the tint as soon as the offset left zero.
    static func tabTintBrightness(for appearance: ThemeAppearance) -> Double {
        let lcdBrightness = appearance.lcdActiveBrightness
        let accentOffset = appearance.accentColor.brightness - appearance.lcdAccentColor.brightness
        guard accentOffset < 0 else { return lcdBrightness + accentOffset }
        return max(0, lcdBrightness * (1 + accentOffset))
    }

    var body: some View {
        TabView(selection: $selectedPage) {
            Tab(AppSection.playlist.title, systemImage: AppSection.playlist.systemImage, value: AppSection.playlist) {
                PlaylistView(selectedPlaycut: $selectedPlaycut, zoomNamespace: playcutZoom)
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
                    #if DEBUG || DEBUG_TESTFLIGHT
                    // The on-air banner's sole debug-panel wiring: overrides the
                    // shipping theme with a live snapshot of OnAirDebugState, so the
                    // debug panel's sliders keep tuning the banner in real time.
                    // PlaylistView and OnAirBannerView never reference OnAirDebugState
                    // themselves — compiled away entirely outside this gate, so it's
                    // absent from a Release build (WXYC/wxyc-ios-64#752).
                    .environment(\.onAirBannerTheme, OnAirBannerTheme.debugOverride)
                    #endif
            }
            .accessibilityIdentifier(AppSection.playlist.accessibilityIdentifier)

            Tab(AppSection.onTour.title, systemImage: AppSection.onTour.systemImage, value: AppSection.onTour) {
                OnTourTabView(model: appState.marketingOnTourModel ?? appState.onTourModel)
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(AppSection.onTour.accessibilityIdentifier)

            Tab(AppSection.liked.title, systemImage: AppSection.liked.systemImage, value: AppSection.liked) {
                LikedTabView()
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(AppSection.liked.accessibilityIdentifier)

            Tab(AppSection.station.title, systemImage: AppSection.station.systemImage, value: AppSection.station) {
                StationView()
                    .themePickerGesture(
                        pickerState: appState.themePickerState,
                        configuration: appState.themeConfiguration
                    )
                    .clearTabBarBackground()
            }
            .accessibilityIdentifier(AppSection.station.accessibilityIdentifier)
        }
        // Selected tab item uses the accent hue/saturation at the brightness from
        // `tabTintBrightness(for:)` rather than the system default tint.
        .tint(appearance.accentColor.color(brightness: Self.tabTintBrightness(for: appearance)))
        // The playcut detail is presented like the On Tour concert detail: a
        // full-screen cover the tapped row zooms into, rather than the old
        // partial-height overlay sheet.
        .playcutDetailCover(selection: $selectedPlaycut, in: playcutZoom)
        // A shared show link arrived: switch to On Tour so the tab materializes and
        // its resolution ladder (`OnTourTabView`) can open the show. Reacting here —
        // not in `OnTourTabView` — guarantees the tab is built even when it wasn't
        // the visible one. The tab consumes and clears the link once resolved.
        .onChange(of: appState.pendingConcertLink) { _, link in
            if link != nil {
                selectedPage = .onTour
            }
        }
        // A playcut deep link arrived (#434): switch to Now Playing so the tab
        // materializes and its `ScrollViewReader` can scroll to the row, even
        // when Now Playing wasn't the visible tab. `PlaylistView` consumes and
        // clears the link once it's handled the scroll (or determined the row
        // isn't currently loaded).
        .onChange(of: appState.pendingPlaycutLink) { _, link in
            if link != nil {
                selectedPage = .playlist
            }
        }
        // An `OpenVenue` intent arrived (OT-C4): switch to On Tour so the tab
        // materializes and can narrow its venue filter, even when On Tour
        // wasn't the visible tab. `OnTourTabView` consumes and clears the
        // link once it's applied the filter.
        .onChange(of: appState.pendingVenueLink) { _, link in
            if link != nil {
                selectedPage = .onTour
            }
        }
        // A `-marketing` recording drives tab navigation from outside the view,
        // exactly like the shared-show-link case above. Nil is a no-op — it never
        // fires for a production launch (`marketingRoute` stays nil).
        .onChange(of: appState.marketingRoute) { _, route in
            if let route {
                selectedPage = route.section
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(Singletonia.shared)
        .environment(\.playlistService, .preview)
}
