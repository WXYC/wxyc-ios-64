//
//  AppSection.swift
//  WXYC
//
//  The app's four top-level navigation sections, hoisted out of
//  `RootTabView.Page` so the (iOS-only) tab view and a future native macOS
//  navigation model can both name the same destinations. Deliberately free of
//  SwiftUI and platform imports so it compiles into every target unchanged.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// A top-level destination in the app — the sections the listener moves
/// between. Shared by the iOS `RootTabView` and, later, the macOS navigation
/// model, so both speak the same vocabulary of sections.
enum AppSection: CaseIterable {
    case playlist
    case onTour
    case liked
    case station

    /// Section label. Also the accessibility label the tab bar exposes.
    var title: String {
        switch self {
        case .playlist: "Now Playing"
        case .onTour: "On Tour"
        case .liked: "Liked"
        case .station: "Station"
        }
    }

    /// SF Symbol for the section glyph — iconography the app already speaks on
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

    /// Stable identifier for UI tests to select the section, independent of the
    /// localized title or the tab bar's element type.
    var accessibilityIdentifier: String {
        switch self {
        case .playlist: "tab.nowPlaying"
        case .onTour: "tab.onTour"
        case .liked: "tab.liked"
        case .station: "tab.station"
        }
    }
}
