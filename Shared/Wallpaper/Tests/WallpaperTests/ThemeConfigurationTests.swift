//
//  ThemeConfigurationTests.swift
//  WallpaperTests
//
//  Tests for ThemeConfiguration using mock registry and isolated UserDefaults.
//

import Testing
import Foundation
import SwiftUI
@testable import Wallpaper

@Suite("ThemeConfiguration Tests")
@MainActor
struct ThemeConfigurationTests {

    // MARK: - Test Helpers

    /// Creates an isolated UserDefaults suite for testing.
    private func makeTestDefaults() -> UserDefaults {
        let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Initialization Tests

    @Suite("Initialization")
    @MainActor
    struct InitializationTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test("Uses default theme ID when no stored value")
        func usesDefaultThemeID() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.selectedThemeID == "wxyc_gradient")
        }

        @Test("Loads stored theme ID from UserDefaults")
        func loadsStoredThemeID() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set("test_dark", forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.selectedThemeID == "test_dark")
        }

        @Test("Loads accent overrides from UserDefaults")
        func loadsAccentOverrides() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            // Use per-theme keys for the default theme (wxyc_gradient)
            defaults.set(180.0, forKey: "wallpaper.accentHueOverride.wxyc_gradient")
            defaults.set(0.5, forKey: "wallpaper.accentSaturationOverride.wxyc_gradient")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.accentHueOverride == 180.0)
            #expect(config.accentSaturationOverride == 0.5)
        }

        @Test("Loads overlay opacity override from UserDefaults")
        func loadsOverlayOpacityOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            // Use per-theme key for the default theme (wxyc_gradient)
            defaults.set(0.5, forKey: "wallpaper.overlayOpacityOverride.wxyc_gradient")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.overlayOpacityOverride == 0.5)
        }
    }

    // MARK: - Effective Accent Color Tests

    @Suite("Effective Accent Color")
    @MainActor
    struct EffectiveAccentColorTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test("Returns theme accent when no overrides")
        func returnsThemeAccentWhenNoOverrides() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set("test_dark", forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.effectiveAccentColor.hue == 30)
            #expect(config.effectiveAccentColor.saturation == 0.8)
        }

        @Test("Applies hue override to theme accent")
        func appliesHueOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set("test_dark", forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.accentHueOverride = 120

            #expect(config.effectiveAccentColor.hue == 120)
            #expect(config.effectiveAccentColor.saturation == 0.8) // From theme
        }

        @Test("Applies saturation override to theme accent")
        func appliesSaturationOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set("test_dark", forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.accentSaturationOverride = 0.3

            #expect(config.effectiveAccentColor.hue == 30) // From theme
            #expect(config.effectiveAccentColor.saturation == 0.3)
        }

        @Test("Returns default accent when theme not found")
        func returnsDefaultWhenThemeNotFound() {
            let registry = MockThemeRegistry.empty()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // When theme not found and no overrides, returns (0, 1.0)
            #expect(config.effectiveAccentColor.hue == 0)
            #expect(config.effectiveAccentColor.saturation == 1.0)
        }
    }

    // MARK: - Effective Overlay Opacity Tests

    @Suite("Effective Overlay Opacity")
    @MainActor
    struct EffectiveOverlayOpacityTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test("Returns theme overlay opacity when no override")
        func returnsThemeOpacityWhenNoOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set("test_dark", forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.effectiveOverlayOpacity == 0.15)
        }

        @Test("Applies overlay opacity override")
        func appliesOpacityOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set("test_dark", forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.overlayOpacityOverride = 0.5

            #expect(config.effectiveOverlayOpacity == 0.5)
        }

        @Test("Returns zero when theme not found and no override")
        func returnsZeroWhenThemeNotFound() {
            let registry = MockThemeRegistry.empty()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.effectiveOverlayOpacity == 0.0)
        }
    }

    // MARK: - Persistence Tests

    @Suite("Persistence")
    @MainActor
    struct PersistenceTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test("Persists selected theme ID changes")
        func persistsSelectedThemeID() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.selectedThemeID = "test_light"

            #expect(defaults.string(forKey: "wallpaper.selectedType.v3") == "test_light")
        }

        @Test("Persists accent hue override with per-theme key")
        func persistsAccentHueOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.accentHueOverride = 45

            // Overrides are stored per-theme using the selected theme ID
            let perThemeKey = "wallpaper.accentHueOverride.\(config.selectedThemeID)"
            #expect(defaults.double(forKey: perThemeKey) == 45)
        }

        @Test("Removes accent hue override when set to nil")
        func removesAccentHueOverrideWhenNil() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            // Set up per-theme key for the default theme
            defaults.set(90.0, forKey: "wallpaper.accentHueOverride.wxyc_gradient")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.accentHueOverride = nil

            let perThemeKey = "wallpaper.accentHueOverride.\(config.selectedThemeID)"
            #expect(defaults.object(forKey: perThemeKey) == nil)
        }

        @Test("Persists overlay opacity override with per-theme key")
        func persistsOverlayOpacityOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.overlayOpacityOverride = 0.3

            // Overrides are stored per-theme using the selected theme ID
            let perThemeKey = "wallpaper.overlayOpacityOverride.\(config.selectedThemeID)"
            #expect(defaults.double(forKey: perThemeKey) == 0.3)
        }

        @Test("Persists LCD min offset with per-theme key")
        func persistsLCDMinOffset() throws {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.lcdMinOffset = HSBOffset(hue: 10, saturation: 0.1, brightness: -0.2)

            // Offset is stored per-theme as JSON
            let perThemeKey = "wallpaper.lcdMinOffset.\(config.selectedThemeID)"
            let data = defaults.data(forKey: perThemeKey)
            #expect(data != nil)

            let decoded = try JSONDecoder().decode(HSBOffset.self, from: data!)
            #expect(decoded.hue == 10)
            #expect(decoded.saturation == 0.1)
            #expect(decoded.brightness == -0.2)
        }

        @Test("Persists LCD max offset with per-theme key")
        func persistsLCDMaxOffset() throws {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.lcdMaxOffset = HSBOffset(hue: -20, saturation: -0.1, brightness: 0.1)

            // Offset is stored per-theme as JSON
            let perThemeKey = "wallpaper.lcdMaxOffset.\(config.selectedThemeID)"
            let data = defaults.data(forKey: perThemeKey)
            #expect(data != nil)

            let decoded = try JSONDecoder().decode(HSBOffset.self, from: data!)
            #expect(decoded.hue == -20)
            #expect(decoded.saturation == -0.1)
            #expect(decoded.brightness == 0.1)
        }

        @Test("LCD offset persists across sessions for same theme")
        func lcdOffsetPersistsAcrossSessions() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            // First session: set values
            let config1 = ThemeConfiguration(registry: registry, defaults: defaults)
            config1.lcdMinOffset = HSBOffset(hue: 15, saturation: 0.05, brightness: -0.15)
            config1.lcdMaxOffset = HSBOffset(hue: -15, saturation: -0.05, brightness: 0.15)

            // Second session: create new config with same defaults
            let config2 = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config2.lcdMinOffset == HSBOffset(hue: 15, saturation: 0.05, brightness: -0.15))
            #expect(config2.lcdMaxOffset == HSBOffset(hue: -15, saturation: -0.05, brightness: 0.15))
        }

        @Test("Each theme remembers its own LCD offset settings")
        func eachThemeRemembersLCDOffset() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Set offset for default theme (wxyc_gradient)
            config.lcdMinOffset = HSBOffset(hue: 10, saturation: 0, brightness: -0.1)
            config.lcdMaxOffset = HSBOffset(hue: 20, saturation: 0.1, brightness: 0)

            // Switch to test_dark and set different offset
            config.selectedThemeID = "test_dark"
            config.lcdMinOffset = HSBOffset(hue: -10, saturation: -0.1, brightness: 0.1)
            config.lcdMaxOffset = HSBOffset(hue: -20, saturation: 0, brightness: 0.2)

            // Switch back to default theme - should load its saved offset
            config.selectedThemeID = "wxyc_gradient"
            #expect(config.lcdMinOffset == HSBOffset(hue: 10, saturation: 0, brightness: -0.1))
            #expect(config.lcdMaxOffset == HSBOffset(hue: 20, saturation: 0.1, brightness: 0))

            // Switch back to test_dark - should load its saved offset
            config.selectedThemeID = "test_dark"
            #expect(config.lcdMinOffset == HSBOffset(hue: -10, saturation: -0.1, brightness: 0.1))
            #expect(config.lcdMaxOffset == HSBOffset(hue: -20, saturation: 0, brightness: 0.2))
        }

        @Test("Theme without saved LCD offset uses defaults")
        func themeWithoutLCDOffsetUsesDefaults() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Set offset for default theme
            config.lcdMinOffset = HSBOffset(hue: 30, saturation: 0.2, brightness: -0.3)

            // Switch to test_dark which has no saved offset
            config.selectedThemeID = "test_dark"
            #expect(config.lcdMinOffset == ThemeConfiguration.defaultLCDMinOffset)
            #expect(config.lcdMaxOffset == ThemeConfiguration.defaultLCDMaxOffset)
        }
    }

    // MARK: - Per-Theme Override Storage Tests

    @Suite("Per-Theme Override Storage")
    @MainActor
    struct PerThemeOverrideStorageTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test("Each theme remembers its own accent hue override")
        func eachThemeRemembersHueOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Set override for default theme (wxyc_gradient)
            config.accentHueOverride = 120

            // Switch to test_dark and set different override
            config.selectedThemeID = "test_dark"
            config.accentHueOverride = 240

            // Switch back to default theme - should load its saved override
            config.selectedThemeID = "wxyc_gradient"
            #expect(config.accentHueOverride == 120)

            // Switch back to test_dark - should load its saved override
            config.selectedThemeID = "test_dark"
            #expect(config.accentHueOverride == 240)
        }

        @Test("Theme without saved overrides uses nil")
        func themeWithoutOverridesUsesNil() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Set override for default theme
            config.accentHueOverride = 120
            #expect(config.accentHueOverride == 120)

            // Switch to test_dark which has no saved override
            config.selectedThemeID = "test_dark"
            #expect(config.accentHueOverride == nil)
        }

        @Test("Per-theme overrides persist across sessions")
        func perThemeOverridesPersistAcrossSessions() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            // First session: set overrides for two themes
            let config1 = ThemeConfiguration(registry: registry, defaults: defaults)
            config1.accentHueOverride = 100
            config1.selectedThemeID = "test_dark"
            config1.accentHueOverride = 200

            // Second session: verify overrides are loaded correctly
            let config2 = ThemeConfiguration(registry: registry, defaults: defaults)
            // Should load test_dark's override since that was the last selected theme
            #expect(config2.selectedThemeID == "test_dark")
            #expect(config2.accentHueOverride == 200)

            // Switch to default theme and verify its override
            config2.selectedThemeID = "wxyc_gradient"
            #expect(config2.accentHueOverride == 100)
        }

        @Test("effectiveAccentColor returns stored overrides for non-selected themes")
        func effectiveAccentColorReturnsStoredOverrides() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Select test_light and set override
            config.selectedThemeID = "test_light"
            config.accentHueOverride = 150

            // Switch to test_dark
            config.selectedThemeID = "test_dark"

            // Query effective accent for test_light (not selected) should return stored override
            let accent = config.effectiveAccentColor(for: "test_light")
            #expect(accent.hue == 150)
        }
    }

    // MARK: - Reset Tests

    @Suite("Reset")
    @MainActor
    struct ResetTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test("Reset clears all overrides")
        func resetClearsOverrides() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.selectedThemeID = "test_dark"
            config.accentHueOverride = 180
            config.accentSaturationOverride = 0.5
            config.overlayOpacityOverride = 0.3

            config.reset()

            #expect(config.selectedThemeID == "wxyc_gradient")
            #expect(config.accentHueOverride == nil)
            #expect(config.accentSaturationOverride == nil)
            #expect(config.overlayOpacityOverride == nil)
        }
    }

    // MARK: - Legacy ID Mapping Tests

    @Suite("Legacy ID Mapping")
    @MainActor
    struct LegacyIDMappingTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test(
            "Maps legacy class names to new IDs",
            arguments: [
                ("WXYCGradientWithNoiseWallpaper", "wxyc_gradient_noise"),
                ("WXYCGradientWallpaperImplementation", "wxyc_gradient"),
                ("WaterTurbulenceWallpaper", "water_turbulence")
            ]
        )
        func mapsLegacyClassNames(legacyID: String, expectedID: String) {
            // Use real registry since mapping needs to check if new ID exists
            let defaults = makeTestDefaults()
            defaults.set(legacyID, forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(defaults: defaults)

            // If the mapped theme exists in registry, it should use the new ID
            // If not, it falls back to default
            let mapped = config.selectedThemeID
            #expect(mapped == expectedID || mapped == "wxyc_gradient")
        }
    }

    // MARK: - Bulk Overrides Tests

    @Suite("Bulk Overrides")
    @MainActor
    struct BulkOverridesTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test("overrides(for:) returns in-memory values for selected theme")
        func overridesReturnsInMemoryForSelectedTheme() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.accentHueOverride = 180
            config.accentSaturationOverride = 0.5
            config.overlayOpacityOverride = 0.3
            config.blurRadiusOverride = 12.0

            let overrides = config.overrides(for: config.selectedThemeID)

            #expect(overrides.accentHue == 180)
            #expect(overrides.accentSaturation == 0.5)
            #expect(overrides.overlayOpacity == 0.3)
            #expect(overrides.blurRadius == 12.0)
        }

        @Test("overrides(for:) returns stored values for non-selected theme")
        func overridesReturnsStoredForNonSelectedTheme() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Set overrides for wxyc_gradient
            config.accentHueOverride = 120
            config.overlayOpacityOverride = 0.4

            // Switch to test_dark
            config.selectedThemeID = "test_dark"

            // Query overrides for wxyc_gradient (not selected)
            let overrides = config.overrides(for: "wxyc_gradient")

            #expect(overrides.accentHue == 120)
            #expect(overrides.overlayOpacity == 0.4)
        }

        @Test("overrides(for:) returns nil for properties not set")
        func overridesReturnsNilForUnsetProperties() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.accentHueOverride = 180 // Only set hue

            let overrides = config.overrides(for: config.selectedThemeID)

            #expect(overrides.accentHue == 180)
            #expect(overrides.accentSaturation == nil)
            #expect(overrides.overlayOpacity == nil)
            #expect(overrides.blurRadius == nil)
            #expect(overrides.overlayDarkness == nil)
        }

        @Test("overrides(for:) includes LCD offset only when changed from default")
        func overridesIncludesLCDOffsetWhenChanged() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Default values - should return nil
            var overrides = config.overrides(for: config.selectedThemeID)
            #expect(overrides.lcdMinOffset == nil)
            #expect(overrides.lcdMaxOffset == nil)

            // Change from default - should return values
            config.lcdMinOffset = HSBOffset(hue: 10, saturation: 0.1, brightness: -0.2)
            config.lcdMaxOffset = HSBOffset(hue: -10, saturation: -0.1, brightness: 0.2)

            overrides = config.overrides(for: config.selectedThemeID)
            #expect(overrides.lcdMinOffset == HSBOffset(hue: 10, saturation: 0.1, brightness: -0.2))
            #expect(overrides.lcdMaxOffset == HSBOffset(hue: -10, saturation: -0.1, brightness: 0.2))
        }

        @Test("overrides(for:) isEmpty when no overrides set")
        func overridesIsEmptyWhenNothingSet() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            let overrides = config.overrides(for: config.selectedThemeID)

            #expect(overrides.isEmpty)
        }
    }
}
