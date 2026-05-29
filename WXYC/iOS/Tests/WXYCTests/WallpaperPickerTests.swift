//
//  WallpaperPickerTests.swift
//  WXYC
//
//  Tests for theme picker state management.
//
//  Created by Jake Bromberg on 12/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Analytics
@testable import Wallpaper

// MARK: - ThemePickerState Tests

@Suite("ThemePickerState Tests")
@MainActor
struct ThemePickerStateTests {

    @Test("Initial state is inactive")
    func initialStateIsInactive() {
        let state = makeState()

        #expect(state.isActive == false)
        #expect(state.centeredThemeID == "")
        #expect(state.carouselIndex == 0)
    }

    @Test("Enter sets active state")
    func enterSetsActiveState() {
        let state = makeState()
        let testThemeID = ThemeRegistry.shared.themes.first?.id ?? "test"

        state.enter(currentThemeID: testThemeID)

        #expect(state.isActive == true)
        #expect(state.centeredThemeID == testThemeID)
    }

    @Test("Enter sets correct carousel index for each theme")
    func enterSetsCorrectCarouselIndex() {
        let state = makeState()
        let themes = ThemeRegistry.shared.themes

        for (expectedIndex, theme) in themes.enumerated() {
            state.enter(currentThemeID: theme.id)

            #expect(state.carouselIndex == expectedIndex, "Expected index \(expectedIndex) for theme '\(theme.id)', but got \(state.carouselIndex)")
            #expect(state.centeredThemeID == theme.id)
        }
    }

    @Test("Exit clears active state")
    func exitClearsActiveState() {
        let state = makeState()

        state.enter(currentThemeID: "test")
        #expect(state.isActive == true)

        state.exit()
        #expect(state.isActive == false)
    }

    @Test("Update centered theme")
    func updateCenteredTheme() {
        let state = makeState()
        let themes = ThemeRegistry.shared.themes

        guard themes.count >= 2 else {
            return // Skip if not enough themes
        }

        state.updateCenteredTheme(forIndex: 1)

        #expect(state.carouselIndex == 1)
        #expect(state.centeredThemeID == themes[1].id)
    }

    @Test("Confirm selection updates configuration")
    func confirmSelectionUpdatesConfiguration() {
        let state = makeState()
        let configuration = ThemeConfiguration()

        let themes = ThemeRegistry.shared.themes
        guard let firstTheme = themes.first,
              let secondTheme = themes.dropFirst().first else {
            return
        }

        // Set initial selection
        configuration.selectedThemeID = firstTheme.id

        // Enter picker and move to second theme
        state.enter(currentThemeID: firstTheme.id)
        state.updateCenteredTheme(forIndex: 1)

        // Confirm selection
        state.confirmSelection(to: configuration)

        #expect(configuration.selectedThemeID == secondTheme.id)
    }
}

// MARK: - ThemeRegistry Tests

@Suite("ThemeRegistry Tests")
@MainActor
struct ThemeRegistryTests {

    @Test("Registry contains themes")
    func registryContainsThemes() {
        let themes = ThemeRegistry.shared.themes

        #expect(themes.isEmpty == false)
    }

    @Test("Themes have unique IDs")
    func themesHaveUniqueIDs() {
        let themes = ThemeRegistry.shared.themes
        let ids = Set(themes.map(\.id))

        #expect(ids.count == themes.count)
    }

    @Test("Themes have display names")
    func themesHaveDisplayNames() {
        for theme in ThemeRegistry.shared.themes {
            #expect(theme.displayName.isEmpty == false)
        }
    }
}

// MARK: - Test Helpers

@MainActor
private func makeState() -> ThemePickerState {
    ThemePickerState(analytics: NoopAnalytics())
}

/// No-op AnalyticsService for hermetic tests that don't assert on analytics.
/// Avoids routing captures through the process-wide StructuredPostHogAnalytics.shared.
private final class NoopAnalytics: AnalyticsService, @unchecked Sendable {
    func capture<T: AnalyticsEvent>(_ event: T) {}
}

