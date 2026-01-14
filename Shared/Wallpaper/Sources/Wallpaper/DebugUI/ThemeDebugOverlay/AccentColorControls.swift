//
//  AccentColorControls.swift
//  Wallpaper
//
//  Controls for adjusting the theme's accent color hue, saturation, and brightness.
//
//  Created by Jake Bromberg on 12/18/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import ColorPalette
import SwiftUI

#if DEBUG
/// Controls for adjusting the theme's accent color hue, saturation, and brightness.
struct AccentColorControls: View {
    @Bindable var configuration: ThemeConfiguration
    let theme: LoadedTheme
    @State private var generatedModeLabel: String?

    private var hueBinding: Binding<Double> {
        Binding(
            get: { configuration.accentHueOverride ?? theme.manifest.accent.hue },
            set: { configuration.accentHueOverride = $0 }
        )
    }

    private var saturationBinding: Binding<Double> {
        Binding(
            get: { configuration.accentSaturationOverride ?? theme.manifest.accent.saturation },
            set: { configuration.accentSaturationOverride = $0 }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { configuration.accentBrightnessOverride ?? theme.manifest.accent.brightness },
            set: { configuration.accentBrightnessOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HSBPicker(
                hueDegrees: hueBinding,
                saturation: saturationBinding,
                brightness: brightnessBinding
            )

            Divider()

            // Generate accent color from wallpaper snapshot
            Button {
                generateAccentFromWallpaper()
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Generate from Wallpaper")
                }
            }
            .font(.caption)

            if let modeLabel = generatedModeLabel {
                Text("Generated using \(modeLabel) palette")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            let hasOverrides =
                configuration.accentHueOverride != nil ||
                configuration.accentSaturationOverride != nil ||
                configuration.accentBrightnessOverride != nil

            if hasOverrides {
                Button("Reset to Theme Default") {
                    configuration.accentHueOverride = nil
                    configuration.accentSaturationOverride = nil
                    configuration.accentBrightnessOverride = nil
                    generatedModeLabel = nil
                }
                .font(.caption)
            }
        }
    }

    private func generateAccentFromWallpaper() {
        // Capture snapshot from the active wallpaper renderer
        guard let snapshot = MetalWallpaperRenderer.captureMainSnapshot() else { return }

        // Extract dominant color
        let extractor = DominantColorExtractor()
        guard let dominantColor = extractor.extractDominantColor(from: snapshot) else { return }

        // Pick a random palette mode
        let allModes = PaletteMode.allCases
        guard let randomMode = allModes.randomElement() else { return }

        // Generate palette
        let generator = PaletteGenerator()
        let palette = generator.generatePalette(from: dominantColor, mode: randomMode)

        // Pick a random color from the palette
        guard let selectedColor = palette.colors.randomElement() else { return }

        // Apply to accent color overrides
        configuration.accentHueOverride = selectedColor.hue
        configuration.accentSaturationOverride = selectedColor.saturation
        configuration.accentBrightnessOverride = selectedColor.brightness

        // Update label to show which mode was used
        generatedModeLabel = randomMode.rawValue
    }
}
#endif
