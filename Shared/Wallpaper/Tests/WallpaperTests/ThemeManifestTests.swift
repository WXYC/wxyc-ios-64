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
