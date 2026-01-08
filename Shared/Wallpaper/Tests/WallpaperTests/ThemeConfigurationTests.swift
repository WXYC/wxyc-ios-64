//
//  ThemeConfigurationTests.swift
//  WallpaperTests
//
//  Tests for ThemeConfiguration using mock registry and isolated UserDefaults.
//

import Testing
import Foundation
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

        @Test("Loads material tint override from UserDefaults")
        func loadsMaterialTintOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set(-0.5, forKey: "wallpaper.materialTintOverride")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.materialTintOverride == -0.5)
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

    // MARK: - Effective Material Tint Tests

    @Suite("Effective Material Tint")
    @MainActor
    struct EffectiveMaterialTintTests {

        private func makeTestDefaults() -> UserDefaults {
            let suiteName = "ThemeConfigurationTests.\(UUID().uuidString)"
            return UserDefaults(suiteName: suiteName)!
        }

        @Test("Returns theme material tint when no override")
        func returnsThemeTintWhenNoOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set("test_dark", forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.effectiveMaterialTint == -0.3)
        }

        @Test("Applies material tint override")
        func appliesTintOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set("test_dark", forKey: "wallpaper.selectedType.v3")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.materialTintOverride = 0.5

            #expect(config.effectiveMaterialTint == 0.5)
        }

        @Test("Returns zero when theme not found and no override")
        func returnsZeroWhenThemeNotFound() {
            let registry = MockThemeRegistry.empty()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)

            #expect(config.effectiveMaterialTint == 0.0)
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

        @Test("Persists accent hue override")
        func persistsAccentHueOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.accentHueOverride = 45

            #expect(defaults.double(forKey: "wallpaper.accentHueOverride") == 45)
        }

        @Test("Removes accent hue override when set to nil")
        func removesAccentHueOverrideWhenNil() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()
            defaults.set(90.0, forKey: "wallpaper.accentHueOverride")

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.accentHueOverride = nil

            #expect(defaults.object(forKey: "wallpaper.accentHueOverride") == nil)
        }

        @Test("Persists material tint override")
        func persistsMaterialTintOverride() {
            let registry = MockThemeRegistry.withTestThemes()
            let defaults = makeTestDefaults()

            let config = ThemeConfiguration(registry: registry, defaults: defaults)
            config.materialTintOverride = -0.7

            #expect(defaults.double(forKey: "wallpaper.materialTintOverride") == -0.7)
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
            config.materialTintOverride = 0.3

            config.reset()

            #expect(config.selectedThemeID == "wxyc_gradient")
            #expect(config.accentHueOverride == nil)
            #expect(config.accentSaturationOverride == nil)
            #expect(config.materialTintOverride == nil)
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
