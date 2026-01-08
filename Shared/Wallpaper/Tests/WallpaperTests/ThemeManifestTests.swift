//
//  ThemeManifestTests.swift
//  WallpaperTests
//
//  Tests for ThemeManifest decoding and MaterialWeight functionality.
//

import Testing
import SwiftUI
@testable import Wallpaper

@Suite("ThemeManifest Tests")
struct ThemeManifestTests {

    // MARK: - MaterialWeight Tests

    @Suite("MaterialWeight")
    struct MaterialWeightTests {

        @Test(
            "MaterialWeight decodes from JSON and maps to correct Material",
            arguments: [
                ("ultraThin", MaterialWeight.ultraThin),
                ("thin", MaterialWeight.thin),
                ("regular", MaterialWeight.regular),
                ("thick", MaterialWeight.thick),
                ("ultraThick", MaterialWeight.ultraThick)
            ]
        )
        @MainActor
        func materialWeightDecodesAndMapsCorrectly(jsonValue: String, expected: MaterialWeight) throws {
            let json = "\"\(jsonValue)\""
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(MaterialWeight.self, from: data)
            #expect(decoded == expected)
        }

        @Test(
            "MaterialWeight encodes to JSON correctly",
            arguments: MaterialWeight.allCases
        )
        func materialWeightEncodesToJSON(weight: MaterialWeight) throws {
            let encoder = JSONEncoder()
            let data = try encoder.encode(weight)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "\"\(weight.rawValue)\"")
        }
    }

    // MARK: - ThemeManifest Decoding Tests

    @Suite("ThemeManifest JSON Decoding")
    struct ThemeManifestDecodingTests {

        @Test(
            "ThemeManifest decodes materialWeight from JSON",
            arguments: MaterialWeight.allCases
        )
        @MainActor
        func themeManifestDecodesMaterialWeight(weight: MaterialWeight) throws {
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
                "materialWeight": "\(weight.rawValue)",
                "materialTint": 0.0
            }
            """
            let data = Data(json.utf8)
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

            #expect(manifest.materialWeight == weight)
        }
    }

    // MARK: - Theme Registry Integration Tests

    @Suite("ThemeRegistry Integration")
    struct ThemeRegistryIntegrationTests {

        @Test("All registered themes have valid materialWeight")
        @MainActor
        func allThemesHaveValidMaterialWeight() {
            let themes = ThemeRegistry.shared.themes

            for theme in themes {
                let weight = theme.manifest.materialWeight
                #expect(MaterialWeight.allCases.contains(weight), "Theme '\(theme.manifest.id)' has unexpected materialWeight")
            }
        }
    }
}
