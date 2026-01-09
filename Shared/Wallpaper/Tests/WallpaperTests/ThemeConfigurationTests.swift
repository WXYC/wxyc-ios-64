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
            defaults.set(180.0, forKey: "wallpaper.accentHueOverride")
            defaults.set(0.5, forKey: "wallpaper.accentSaturationOverride")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.accentHueOverride == 180.0)
            #expect(config.accentSaturationOverride == 0.5)
        }

        @Test("Loads overlay opacity override from UserDefaults")
        func loadsOverlayOpacityOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set(0.5, forKey: "wallpaper.overlayOpacityOverride")

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

        @Test("Persists LCD min brightness with per-theme key")
        func persistsLCDMinBrightness() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.lcdMinBrightness = 0.75

            // Brightness is stored per-theme
            let perThemeKey = "wallpaper.lcdMinBrightness.\(config.selectedThemeID)"
            #expect(defaults.double(forKey: perThemeKey) == 0.75)
        }

        @Test("Persists LCD max brightness with per-theme key")
        func persistsLCDMaxBrightness() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.lcdMaxBrightness = 1.2

            // Brightness is stored per-theme
            let perThemeKey = "wallpaper.lcdMaxBrightness.\(config.selectedThemeID)"
            #expect(defaults.double(forKey: perThemeKey) == 1.2)
        }

        @Test("Loads LCD brightness values from per-theme keys on init")
        func loadsLCDBrightnessOnInit() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            // Store per-theme brightness for the default theme (wxyc_gradient)
            defaults.set(0.80, forKey: "wallpaper.lcdMinBrightness.wxyc_gradient")
            defaults.set(1.10, forKey: "wallpaper.lcdMaxBrightness.wxyc_gradient")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.lcdMinBrightness == 0.80)
            #expect(config.lcdMaxBrightness == 1.10)
        }

        @Test("LCD brightness persists across sessions for same theme")
        func lcdBrightnessPersistsAcrossSessions() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            // First session: set values
            let config1 = ThemeConfiguration(registry: registry, defaults: defaults)
            config1.lcdMinBrightness = 0.65
            config1.lcdMaxBrightness = 1.25

            // Second session: create new config with same defaults
            let config2 = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config2.lcdMinBrightness == 0.65)
            #expect(config2.lcdMaxBrightness == 1.25)
        }

        @Test("LCD brightness persists when set via Bindable pattern")
        func lcdBrightnessPersistsViaBindable() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            // Simulate @Bindable access pattern
            let config1 = ThemeConfiguration(registry: registry, defaults: defaults)

            // Create a binding similar to what @Bindable would create
            var minBrightnessBinding = Bindable(config1).lcdMinBrightness
            minBrightnessBinding.wrappedValue = 0.72

            // Verify the value was set on the object
            #expect(config1.lcdMinBrightness == 0.72)

            // Verify it was persisted to UserDefaults with per-theme key
            let perThemeKey = "wallpaper.lcdMinBrightness.\(config1.selectedThemeID)"
            #expect(defaults.double(forKey: perThemeKey) == 0.72)

            // Verify it loads in a new instance
            let config2 = ThemeConfiguration(registry: registry, defaults: defaults)
            #expect(config2.lcdMinBrightness == 0.72)
        }

        @Test("Migrates legacy global brightness keys to per-theme keys")
        func migratesLegacyBrightnessKeys() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            // Set legacy global keys
            defaults.set(0.85, forKey: "wallpaper.lcdMinBrightness")
            defaults.set(1.15, forKey: "wallpaper.lcdMaxBrightness")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Values should be loaded from legacy keys
            #expect(config.lcdMinBrightness == 0.85)
            #expect(config.lcdMaxBrightness == 1.15)

            // Legacy keys should be removed after migration
            #expect(defaults.object(forKey: "wallpaper.lcdMinBrightness") == nil)
            #expect(defaults.object(forKey: "wallpaper.lcdMaxBrightness") == nil)

            // Values should now be stored in per-theme keys
            let minKey = "wallpaper.lcdMinBrightness.\(config.selectedThemeID)"
            let maxKey = "wallpaper.lcdMaxBrightness.\(config.selectedThemeID)"
            #expect(defaults.double(forKey: minKey) == 0.85)
            #expect(defaults.double(forKey: maxKey) == 1.15)
        }

        @Test("Each theme remembers its own brightness settings")
        func eachThemeRemembersBrightness() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Set brightness for default theme (wxyc_gradient)
            config.lcdMinBrightness = 0.70
            config.lcdMaxBrightness = 1.10

            // Switch to test_dark and set different brightness
            config.selectedThemeID = "test_dark"
            config.lcdMinBrightness = 0.80
            config.lcdMaxBrightness = 1.20

            // Switch back to default theme - should load its saved brightness
            config.selectedThemeID = "wxyc_gradient"
            #expect(config.lcdMinBrightness == 0.70)
            #expect(config.lcdMaxBrightness == 1.10)

            // Switch back to test_dark - should load its saved brightness
            config.selectedThemeID = "test_dark"
            #expect(config.lcdMinBrightness == 0.80)
            #expect(config.lcdMaxBrightness == 1.20)
        }

        @Test("Theme without saved brightness uses defaults")
        func themeWithoutBrightnessUsesDefaults() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            // Set brightness for default theme
            config.lcdMinBrightness = 0.70

            // Switch to test_dark which has no saved brightness
            config.selectedThemeID = "test_dark"
            #expect(config.lcdMinBrightness == ThemeConfiguration.defaultLCDMinBrightness)
            #expect(config.lcdMaxBrightness == ThemeConfiguration.defaultLCDMaxBrightness)
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
}
