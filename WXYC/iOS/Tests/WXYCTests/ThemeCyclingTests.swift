//
//  ThemeCyclingTests.swift
//  WXYC
//
//  Tests for `ThemeCycling`: the wrap-around step math behind the j/k keyboard
//  shortcuts, and the two ways a step lands — committed instantly when the
//  picker is closed, previewed in the carousel when it is open.
//
//  Created by Jake Bromberg on 08/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Caching
import Testing
import Wallpaper
@testable import WXYC

// A three-theme list is the smallest that distinguishes "steps" from "wraps".
// `nonisolated` because Swift Testing evaluates `arguments:` off the main actor,
// which this target's default isolation would otherwise put the constant on.
private nonisolated let cyclingSteps: [(current: String, direction: ThemeCycling.Direction, expected: String)] = [
    ("a", .next, "b"),
    ("b", .next, "c"),
    ("c", .next, "a"),
    ("c", .previous, "b"),
    ("b", .previous, "a"),
    ("a", .previous, "c"),
    // A stored theme the registry no longer knows about must still land
    // somewhere real rather than stranding the user on the fallback accent.
    ("unknown", .next, "a"),
    ("unknown", .previous, "c")
]

@Suite("Theme cycling")
@MainActor
struct ThemeCyclingTests {

    // MARK: - Step math

    @Test("Steps through the list and wraps at both ends", arguments: cyclingSteps)
    func stepsAndWraps(step: (current: String, direction: ThemeCycling.Direction, expected: String)) {
        let result = ThemeCycling.themeID(
            after: step.current,
            in: ["a", "b", "c"],
            direction: step.direction
        )

        #expect(result == step.expected)
    }

    @Test("Has nowhere to go with no themes", arguments: [ThemeCycling.Direction.next, .previous])
    func emptyRegistryHasNoDestination(direction: ThemeCycling.Direction) {
        #expect(ThemeCycling.themeID(after: "a", in: [], direction: direction) == nil)
    }

    @Test("Has nowhere to go with a single theme", arguments: [ThemeCycling.Direction.next, .previous])
    func singleThemeHasNoDestination(direction: ThemeCycling.Direction) {
        #expect(ThemeCycling.themeID(after: "a", in: ["a"], direction: direction) == nil)
    }

    // MARK: - Applying a step

    @Test("Commits the new theme immediately when the picker is closed")
    func commitsInstantlyWithPickerClosed() throws {
        let themes = ThemeRegistry.shared.themes
        try #require(themes.count >= 2)
        let configuration = ThemeConfiguration(defaults: InMemoryDefaults())
        configuration.selectedThemeID = themes[0].id
        let pickerState = ThemePickerState(analytics: NoopAnalytics())

        let landed = ThemeCycling.cycle(.next, configuration: configuration, pickerState: pickerState)

        #expect(landed == themes[1].id)
        #expect(configuration.selectedThemeID == themes[1].id)
        // Switching must not drag the user into picker mode.
        #expect(pickerState.isActive == false)
    }

    @Test("Steps backwards from the first theme onto the last")
    func wrapsBackwardsWithPickerClosed() throws {
        let themes = ThemeRegistry.shared.themes
        try #require(themes.count >= 2)
        let configuration = ThemeConfiguration(defaults: InMemoryDefaults())
        configuration.selectedThemeID = themes[0].id
        let pickerState = ThemePickerState(analytics: NoopAnalytics())

        ThemeCycling.cycle(.previous, configuration: configuration, pickerState: pickerState)

        #expect(configuration.selectedThemeID == themes[themes.count - 1].id)
    }

    @Test("Moves the carousel without committing when the picker is open")
    func previewsWithPickerOpen() throws {
        let themes = ThemeRegistry.shared.themes
        try #require(themes.count >= 2)
        let configuration = ThemeConfiguration(defaults: InMemoryDefaults())
        configuration.selectedThemeID = themes[0].id
        let pickerState = ThemePickerState(analytics: NoopAnalytics())
        pickerState.enter(currentThemeID: themes[0].id)

        ThemeCycling.cycle(.next, configuration: configuration, pickerState: pickerState)

        #expect(pickerState.centeredThemeID == themes[1].id)
        #expect(pickerState.carouselIndex == 1)
        // The picker commits on confirm, not on every step.
        #expect(configuration.selectedThemeID == themes[0].id)
    }
}

// MARK: - Test Helpers

/// No-op AnalyticsService for hermetic tests that don't assert on analytics.
/// Avoids routing captures through the process-wide StructuredPostHogAnalytics.shared.
private final class NoopAnalytics: AnalyticsService, @unchecked Sendable {
    func capture<T: AnalyticsEvent>(_ event: T) {}
}
