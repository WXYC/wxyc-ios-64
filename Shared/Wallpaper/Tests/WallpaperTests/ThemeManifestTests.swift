//
//  ThemeManifestTests.swift
//  WallpaperTests
//
//  Tests for ThemeManifest decoding and material properties.
//

import Testing
import SwiftUI
@testable import Wallpaper

@Suite("ThemeManifest Tests")
struct ThemeManifestTests {

    // MARK: - Material Properties Tests

    @Suite("Material Properties")
    struct MaterialPropertiesTests {

        @Test("ThemeManifest decodes blur radius from JSON")
        @MainActor
        func themeManifestDecodesBlurRadius() throws {
            let json = """
            {
                "id": "test_theme",
                "displayName": "Test Theme",
                "version": "1.0.0",
                "renderer": { "type": "swiftUI" },
                "parameters": [],
                "shaderArguments": [],
                "foreground": "light",
                "accent": { "hue": 23, "saturation": 0.75 },
                "appIconName": null,
                "blurRadius": 12.0,
                "overlayOpacity": 0.25,
                "overlayIsDark": true
            }
            """
            let data = Data(json.utf8)
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

            #expect(manifest.blurRadius == 12.0)
            #expect(manifest.overlayOpacity == 0.25)
            #expect(manifest.overlayIsDark == true)
        }

        @Test("ThemeManifest decodes light overlay from JSON")
        @MainActor
        func themeManifestDecodesLightOverlay() throws {
            let json = """
            {
                "id": "test_theme",
                "displayName": "Test Theme",
                "version": "1.0.0",
                "renderer": { "type": "swiftUI" },
                "parameters": [],
                "shaderArguments": [],
                "foreground": "light",
                "accent": { "hue": 23, "saturation": 0.75 },
                "appIconName": null,
                "blurRadius": 8.0,
                "overlayOpacity": 0.0,
                "overlayIsDark": false
            }
            """
            let data = Data(json.utf8)
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

            #expect(manifest.blurRadius == 8.0)
            #expect(manifest.overlayOpacity == 0.0)
            #expect(manifest.overlayIsDark == false)
        }
    }

    // MARK: - Override Application Tests

    @Suite("Override Application")
    struct OverrideApplicationTests {

        @Test("applying(_:) merges accent color overrides")
        @MainActor
        func applyingMergesAccentColorOverrides() {
            let manifest = ThemeManifest(
                id: "test",
                displayName: "Test",
                version: "1.0.0",
                renderer: RendererConfiguration(type: .swiftUI),
                foreground: .light,
                accent: AccentColor(hue: 30, saturation: 0.8),
                blurRadius: 8.0,
                overlayOpacity: 0.15,
                overlayIsDark: true
            )

            let overrides = ThemeOverrides(accentHue: 180, accentSaturation: 0.5)
            let result = manifest.applying(overrides)

            #expect(result.accent.hue == 180)
            #expect(result.accent.saturation == 0.5)
        }

        @Test("applying(_:) preserves original values when override is nil")
        @MainActor
        func applyingPreservesOriginalWhenOverrideNil() {
            let manifest = ThemeManifest(
                id: "test",
                displayName: "Test",
                version: "1.0.0",
                renderer: RendererConfiguration(type: .swiftUI),
                foreground: .light,
                accent: AccentColor(hue: 30, saturation: 0.8),
                blurRadius: 8.0,
                overlayOpacity: 0.15,
                overlayIsDark: true
            )

            let overrides = ThemeOverrides() // all nil
            let result = manifest.applying(overrides)

            #expect(result.accent.hue == 30)
            #expect(result.accent.saturation == 0.8)
            #expect(result.blurRadius == 8.0)
            #expect(result.overlayOpacity == 0.15)
            #expect(result.overlayIsDark == true)
        }

        @Test("applying(_:) merges material property overrides")
        @MainActor
        func applyingMergesMaterialOverrides() {
            let manifest = ThemeManifest(
                id: "test",
                displayName: "Test",
                version: "1.0.0",
                renderer: RendererConfiguration(type: .swiftUI),
                foreground: .light,
                accent: AccentColor(hue: 30, saturation: 0.8),
                blurRadius: 8.0,
                overlayOpacity: 0.15,
                overlayIsDark: true
            )

            let overrides = ThemeOverrides(
                overlayOpacity: 0.5,
                blurRadius: 16.0,
                overlayIsDark: false
            )
            let result = manifest.applying(overrides)

            #expect(result.blurRadius == 16.0)
            #expect(result.overlayOpacity == 0.5)
            #expect(result.overlayIsDark == false)
        }

        @Test("applying(_:) merges LCD brightness offset override")
        @MainActor
        func applyingMergesLCDBrightnessOffset() {
            let manifest = ThemeManifest(
                id: "test",
                displayName: "Test",
                version: "1.0.0",
                renderer: RendererConfiguration(type: .swiftUI),
                foreground: .light,
                accent: AccentColor(hue: 30, saturation: 0.8),
                blurRadius: 8.0,
                overlayOpacity: 0.15,
                overlayIsDark: true,
                lcdBrightnessOffset: 0.0
            )

            let overrides = ThemeOverrides(lcdBrightnessOffset: 0.2)
            let result = manifest.applying(overrides)

            #expect(result.lcdBrightnessOffset == 0.2)
        }

        @Test("applying(_:) preserves non-overridable properties")
        @MainActor
        func applyingPreservesNonOverridableProperties() {
            let manifest = ThemeManifest(
                id: "test",
                displayName: "Test Theme",
                version: "2.0.0",
                renderer: RendererConfiguration(type: .swiftUI),
                foreground: .dark,
                accent: AccentColor(hue: 30, saturation: 0.8),
                appIconName: "TestIcon",
                buttonStyle: .glass,
                blurRadius: 8.0,
                overlayOpacity: 0.15,
                overlayIsDark: true
            )

            let overrides = ThemeOverrides(accentHue: 180)
            let result = manifest.applying(overrides)

            #expect(result.id == "test")
            #expect(result.displayName == "Test Theme")
            #expect(result.version == "2.0.0")
            #expect(result.foreground == .dark)
            #expect(result.appIconName == "TestIcon")
            #expect(result.buttonStyle == .glass)
        }
    }

    // MARK: - Theme Registry Integration Tests

    @Suite("ThemeRegistry Integration")
    struct ThemeRegistryIntegrationTests {

        @Test("All registered themes have valid material properties")
        @MainActor
        func allThemesHaveValidMaterialProperties() {
            let themes = ThemeRegistry.shared.themes

            for theme in themes {
                let blurRadius = theme.manifest.blurRadius
                let overlayOpacity = theme.manifest.overlayOpacity

                #expect(blurRadius >= 0, "Theme '\(theme.manifest.id)' has negative blurRadius")
                #expect(overlayOpacity >= 0 && overlayOpacity <= 1, "Theme '\(theme.manifest.id)' has invalid overlayOpacity")
            }
        }
    }
}
