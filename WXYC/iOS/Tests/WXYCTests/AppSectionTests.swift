//
//  AppSectionTests.swift
//  WXYC
//
//  Verifies the top-level `AppSection` metadata. As of the liked-songs feature
//  (#492) there are four sections — Now Playing, On Tour, Liked, Station — each
//  carrying the SF Symbols the app already speaks on adjacent surfaces: radio in
//  the widget and Siri intent, ticket in the Box Office ticket language, heart in
//  the playcut like affordance, and the antenna for the station page (the Info
//  junk drawer regrouped; see docs/ideas/info-tab-junk-drawer.html).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Wallpaper
@testable import WXYC

@Suite("AppSection")
struct AppSectionTests {
    @Test("Four sections in order: Now Playing, On Tour, Liked, Station")
    func caseOrder() {
        #expect(AppSection.allCases == [.playlist, .onTour, .liked, .station])
    }

    @Test("The Now Playing section is labeled for the live stream")
    func nowPlayingMetadata() {
        #expect(AppSection.playlist.title == "Now Playing")
        #expect(AppSection.playlist.systemImage == "radio")
    }

    @Test("The On Tour section is labeled with the ticket glyph")
    func onTourMetadata() {
        #expect(AppSection.onTour.title == "On Tour")
        #expect(AppSection.onTour.systemImage == "ticket")
    }

    @Test("The Liked section is labeled with the heart glyph")
    func likedMetadata() {
        #expect(AppSection.liked.title == "Liked")
        #expect(AppSection.liked.systemImage == "heart")
    }

    @Test("The Station section is labeled with the antenna glyph")
    func stationMetadata() {
        #expect(AppSection.station.title == "Station")
        #expect(AppSection.station.systemImage == "antenna.radiowaves.left.and.right")
    }

    @Test("Each section carries a stable accessibility identifier")
    func accessibilityIdentifiers() {
        #expect(AppSection.playlist.accessibilityIdentifier == "tab.nowPlaying")
        #expect(AppSection.onTour.accessibilityIdentifier == "tab.onTour")
        #expect(AppSection.liked.accessibilityIdentifier == "tab.liked")
        #expect(AppSection.station.accessibilityIdentifier == "tab.station")
    }
}

@Suite("RootTabView tint")
struct RootTabViewTintTests {
    @Test("The tab tint uses LCD active brightness")
    func tabTintBrightnessUsesLCDActiveBrightness() {
        let appearance = ThemeAppearance(
            accentColor: AccentColor(hue: 120, saturation: 0.4, brightness: 0.35),
            lcdActiveBrightness: 1.42
        )

        #expect(RootTabView.tabTintBrightness(for: appearance) == 1.42)
    }
}
