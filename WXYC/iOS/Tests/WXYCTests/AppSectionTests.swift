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

import SwiftUI
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
    /// LCD active brightness, plus whatever the theme's accent offset adds: the accent
    /// and the LCD accent differ by exactly that offset.
    @Test(
        "The tab tint is LCD active brightness moved by the accent offset",
        arguments: [
            // No offset: the tint matches the LCD whatever the accent's own brightness.
            (accent: 0.35, lcdAccent: 0.35, lcdActive: 1.42, expected: 1.42),
            (accent: 0.8, lcdAccent: 0.5, lcdActive: 1.0, expected: 1.3),
            (accent: 0.5, lcdAccent: 0.8, lcdActive: 1.0, expected: 0.7),
            // Lowering scales the LCD value, so -0.2 takes 20% off it.
            (accent: 0.6, lcdAccent: 0.8, lcdActive: 1.5, expected: 1.2),
            // Raising adds to the LCD value.
            (accent: 1.0, lcdAccent: 0.8, lcdActive: 1.24, expected: 1.44),
            // A large negative offset stops at black.
            (accent: 0.0, lcdAccent: 1.0, lcdActive: 0.6, expected: 0.0),
        ]
    )
    func tabTintBrightness(accent: Double, lcdAccent: Double, lcdActive: Double, expected: Double) {
        // Seeded from the environment default rather than the memberwise
        // initializer: `ThemeAppearance` is a submodule type with 13 stored
        // properties, and keyword-constructing it here would make every field
        // this test does not care about a host-side source break the moment
        // Wallpaper adds one or drops a default. Mutating the fields under
        // test keeps the host immune to both without a gitlink bump.
        var appearance = EnvironmentValues().themeAppearance
        appearance.accentColor = AccentColor(hue: 120, saturation: 0.4, brightness: accent)
        appearance.lcdAccentColor = AccentColor(hue: 120, saturation: 0.4, brightness: lcdAccent)
        appearance.lcdActiveBrightness = lcdActive

        #expect(abs(RootTabView.tabTintBrightness(for: appearance) - expected) < 0.000_001)
    }

    /// Sweeps the slider from top to bottom: the tint must only ever get darker, and
    /// by no more than one slider step's worth, so there is no jump anywhere,
    /// including where the offset crosses zero.
    @Test("The tab tint changes smoothly across the whole offset range", arguments: [0.6, 1.0, 1.24, 1.5004])
    func tabTintBrightnessIsContinuous(lcdActive: Double) {
        var appearance = EnvironmentValues().themeAppearance
        appearance.lcdAccentColor = AccentColor(hue: 120, saturation: 0.4, brightness: 1.0)
        appearance.lcdActiveBrightness = lcdActive

        let step = 0.01
        let largestAllowedChange = step * max(lcdActive, 1) + 0.000_001
        var previous: Double?
        for offset in stride(from: 1.0, through: -1.0, by: -step) {
            appearance.accentColor = AccentColor(hue: 120, saturation: 0.4, brightness: 1.0 + offset)
            let brightness = RootTabView.tabTintBrightness(for: appearance)
            if let previous {
                #expect(brightness <= previous)
                #expect(previous - brightness <= largestAllowedChange)
            }
            previous = brightness
        }
    }
}
