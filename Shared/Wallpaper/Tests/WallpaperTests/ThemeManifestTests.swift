//
//  ThemeManifestTests.swift
//  Wallpaper
//
//  Tests for ThemeManifest decoding and material properties.
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
@testable import Wallpaper

@Suite("ThemeManifest Tests")
struct ThemeManifestTests {

    // MARK: - Material Properties Tests

    @Suite("Material Properties")
    struct MaterialPropertiesTests {

        @Test("ThemeManifest decodes material from JSON")
        @MainActor
        func themeManifestDecodesMaterial() throws {
            let json = """
            {
                "id": "test_theme",
                "displayName": "Test Theme",
                "version": "1.0.0",
                "renderer": { "type": "swiftUI" },
                "parameters": [],
                "shaderArguments": [],
                "accent": { "hue": 23, "saturation": 0.75, "brightness": 1.0 },
                "material": {
                    "foreground": "light",
                    "blurRadius": 12.0,
                    "overlay": {
                        "opacity": 0.25,
                        "darkness": 1.0
                    }
                }
            }
            """
            let data = Data(json.utf8)
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

            #expect(manifest.material.foreground == .light)
            #expect(manifest.material.blurRadius == 12.0)
            #expect(manifest.material.overlay.opacity == 0.25)
            #expect(manifest.material.overlay.darkness == 1.0)
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
                "accent": { "hue": 23, "saturation": 0.75, "brightness": 1.0 },
                "material": {
                    "foreground": "light",
                    "blurRadius": 8.0,
                    "overlay": {
                        "opacity": 0.0,
                        "darkness": 0.0
                    }
                }
            }
            """
            let data = Data(json.utf8)
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

            #expect(manifest.material.blurRadius == 8.0)
            #expect(manifest.material.overlay.opacity == 0.0)
            #expect(manifest.material.overlay.darkness == 0.0)
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
                accent: AccentColor(hue: 30, saturation: 0.8),
                material: MaterialConfiguration(
                    foreground: .light,
                    blurRadius: 8.0,
                    overlay: OverlayConfiguration(opacity: 0.15, darkness: 1.0)
                )
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
                accent: AccentColor(hue: 30, saturation: 0.8),
                material: MaterialConfiguration(
                    foreground: .light,
                    blurRadius: 8.0,
                    overlay: OverlayConfiguration(opacity: 0.15, darkness: 1.0)
                )
            )

            let overrides = ThemeOverrides() // all nil
            let result = manifest.applying(overrides)

            #expect(result.accent.hue == 30)
            #expect(result.accent.saturation == 0.8)
            #expect(result.material.blurRadius == 8.0)
            #expect(result.material.overlay.opacity == 0.15)
            #expect(result.material.overlay.darkness == 1.0)
        }

        @Test("applying(_:) merges material property overrides")
        @MainActor
        func applyingMergesMaterialOverrides() {
            let manifest = ThemeManifest(
                id: "test",
                displayName: "Test",
                version: "1.0.0",
                renderer: RendererConfiguration(type: .swiftUI),
                accent: AccentColor(hue: 30, saturation: 0.8),
                material: MaterialConfiguration(
                    foreground: .light,
                    blurRadius: 8.0,
                    overlay: OverlayConfiguration(opacity: 0.15, darkness: 1.0)
                )
            )

            let overrides = ThemeOverrides(
                overlayOpacity: 0.5,
                blurRadius: 16.0,
                overlayDarkness: 0.0
            )
            let result = manifest.applying(overrides)

            #expect(result.material.blurRadius == 16.0)
            #expect(result.material.overlay.opacity == 0.5)
            #expect(result.material.overlay.darkness == 0.0)
        }

        @Test("applying(_:) preserves non-overridable properties")
        @MainActor
        func applyingPreservesNonOverridableProperties() {
            let manifest = ThemeManifest(
                id: "test",
                displayName: "Test Theme",
                version: "2.0.0",
                renderer: RendererConfiguration(type: .swiftUI),
                accent: AccentColor(hue: 30, saturation: 0.8),
                material: MaterialConfiguration(
                    foreground: .dark,
                    blurRadius: 8.0,
                    overlay: OverlayConfiguration(opacity: 0.15, darkness: 1.0)
                ),
                button: .glass(OverlayConfiguration(opacity: 0.15, darkness: 0.5))
            )

            let overrides = ThemeOverrides(accentHue: 180)
            let result = manifest.applying(overrides)

            #expect(result.id == "test")
            #expect(result.displayName == "Test Theme")
            #expect(result.version == "2.0.0")
            #expect(result.material.foreground == .dark)
            if case .glass = result.button {
                // Expected
            } else {
                Issue.record("Expected button to be .glass")
            }
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
                let blurRadius = theme.manifest.material.blurRadius
                let overlayOpacity = theme.manifest.material.overlay.opacity

                #expect(blurRadius >= 0, "Theme '\(theme.manifest.id)' has negative blurRadius")
                #expect(overlayOpacity >= 0 && overlayOpacity <= 1, "Theme '\(theme.manifest.id)' has invalid overlayOpacity")
            }
        }
    }

    // MARK: - Compute Configuration Tests

    @Suite("Compute Configuration")
    struct ComputeConfigurationTests {

        @Test("RendererType includes compute case")
        func rendererTypeIncludesCompute() {
            let computeType = RendererType.compute
            #expect(computeType.rawValue == "compute")
        }

        @Test("ComputeConfiguration decodes from JSON")
        @MainActor
        func computeConfigurationDecodesFromJSON() throws {
            let json = """
            {
                "id": "test_compute",
                "displayName": "Test Compute",
                "version": "1.0.0",
                "renderer": {
                    "type": "compute",
                    "compute": {
                        "passes": [
                            {
                                "name": "update",
                                "functionName": "updateKernel",
                                "threadGroupSize": [32, 32, 1]
                            }
                        ],
                        "renderFunction": "renderFragment",
                        "particleCount": 500000
                    }
                },
                "parameters": [],
                "shaderArguments": [],
                "accent": { "hue": 280, "saturation": 0.7, "brightness": 0.9 },
                "material": {
                    "foreground": "dark",
                    "blurRadius": 8.0,
                    "overlay": {
                        "opacity": 0.15,
                        "darkness": 0.9
                    }
                }
            }
            """
            let data = Data(json.utf8)
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

            #expect(manifest.renderer.type == .compute)
            #expect(manifest.renderer.compute != nil)
            #expect(manifest.renderer.compute?.passes.count == 1)
            #expect(manifest.renderer.compute?.passes.first?.name == "update")
            #expect(manifest.renderer.compute?.passes.first?.functionName == "updateKernel")
            #expect(manifest.renderer.compute?.renderFunction == "renderFragment")
            #expect(manifest.renderer.compute?.particleCount == 500000)
        }

        @Test("ComputePassConfiguration provides default thread group size")
        func computePassConfigurationDefaultThreadGroupSize() {
            let pass = ComputePassConfiguration(
                name: "test",
                functionName: "testKernel"
            )

            let (x, y, z) = pass.effectiveThreadGroupSize
            #expect(x == 32)
            #expect(y == 32)
            #expect(z == 1)
        }

        @Test("ComputePassConfiguration uses custom thread group size")
        func computePassConfigurationCustomThreadGroupSize() {
            let pass = ComputePassConfiguration(
                name: "test",
                functionName: "testKernel",
                threadGroupSize: [16, 16, 4]
            )

            let (x, y, z) = pass.effectiveThreadGroupSize
            #expect(x == 16)
            #expect(y == 16)
            #expect(z == 4)
        }

        @Test("PersistentTextureConfiguration provides defaults")
        func persistentTextureConfigurationDefaults() {
            let texture = PersistentTextureConfiguration(
                name: "trailMap",
                format: "rg16Float"
            )

            #expect(texture.effectiveScale == 1.0)
            #expect(texture.isDoubleBuffered == false)
        }

        @Test("PersistentTextureConfiguration decodes all fields")
        @MainActor
        func persistentTextureConfigurationDecodesAllFields() throws {
            let json = """
            {
                "passes": [],
                "renderFunction": "render",
                "persistentTextures": [
                    {
                        "name": "trailMap",
                        "format": "rg16Float",
                        "scale": 0.5,
                        "doubleBuffered": true
                    }
                ]
            }
            """
            let data = Data(json.utf8)
            let config = try JSONDecoder().decode(ComputeConfiguration.self, from: data)

            #expect(config.persistentTextures?.count == 1)
            let texture = config.persistentTextures?.first
            #expect(texture?.name == "trailMap")
            #expect(texture?.format == "rg16Float")
            #expect(texture?.effectiveScale == 0.5)
            #expect(texture?.isDoubleBuffered == true)
        }

        @Test("ComputeTextureBinding has expected static values")
        func computeTextureBindingStaticValues() {
            #expect(ComputeTextureBinding.trailMap == "trailMap")
            #expect(ComputeTextureBinding.particleBuffer == "particleBuffer")
            #expect(ComputeTextureBinding.counterBuffer == "counterBuffer")
        }

        @Test("ComputeTextureBinding defaults to reading from previous buffer")
        func computeTextureBindingDefaultsToReadPrevious() {
            let binding = ComputeTextureBinding(index: 0, source: "trailMap")
            #expect(binding.shouldReadFromCurrent == false)
            #expect(binding.shouldWriteToPrevious == false)
        }

        @Test("ComputeTextureBinding respects readFromCurrent flag")
        func computeTextureBindingRespectsReadFromCurrent() {
            let binding = ComputeTextureBinding(index: 0, source: "trailMap", readFromCurrent: true)
            #expect(binding.shouldReadFromCurrent == true)
        }

        @Test("ComputeTextureBinding respects writeToPrevious flag")
        func computeTextureBindingRespectsWriteToPrevious() {
            let binding = ComputeTextureBinding(index: 0, source: "trailMap", writeToPrevious: true)
            #expect(binding.shouldWriteToPrevious == true)
        }

        @Test("ComputeTextureBinding decodes readFromCurrent from JSON")
        func computeTextureBindingDecodesReadFromCurrent() throws {
            let json = """
            {
                "passes": [
                    {
                        "name": "diffuse",
                        "functionName": "diffuseKernel",
                        "inputs": [
                            { "index": 0, "source": "trailMap", "readFromCurrent": true }
                        ]
                    }
                ],
                "renderFunction": "render"
            }
            """
            let data = Data(json.utf8)
            let config = try JSONDecoder().decode(ComputeConfiguration.self, from: data)

            let input = config.passes.first?.inputs?.first
            #expect(input?.shouldReadFromCurrent == true)
        }

        @Test("ComputeTextureBinding decodes writeToPrevious from JSON")
        func computeTextureBindingDecodesWriteToPrevious() throws {
            let json = """
            {
                "passes": [
                    {
                        "name": "diffuse",
                        "functionName": "diffuseKernel",
                        "outputs": [
                            { "index": 1, "source": "trailMap", "writeToPrevious": true }
                        ]
                    }
                ],
                "renderFunction": "render"
            }
            """
            let data = Data(json.utf8)
            let config = try JSONDecoder().decode(ComputeConfiguration.self, from: data)

            let output = config.passes.first?.outputs?.first
            #expect(output?.shouldWriteToPrevious == true)
        }
    }
}
