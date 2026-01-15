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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HSBPicker(
                hueDegrees: overrideBinding(
                    get: configuration.accentHueOverride,
                    fallback: theme.manifest.accent.hue,
                    set: { configuration.accentHueOverride = $0 }
                ),
                saturation: overrideBinding(
                    get: configuration.accentSaturationOverride,
                    fallback: theme.manifest.accent.saturation,
                    set: { configuration.accentSaturationOverride = $0 }
                ),
                brightness: overrideBinding(
                    get: configuration.accentBrightnessOverride,
                    fallback: theme.manifest.accent.brightness,
                    set: { configuration.accentBrightnessOverride = $0 }
                )
            )

            Divider()

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

            ConditionalResetButton(
                hasOverrides: configuration.accentHueOverride != nil ||
                              configuration.accentSaturationOverride != nil ||
                              configuration.accentBrightnessOverride != nil,
                label: "Reset to Theme Default"
            ) {
                configuration.accentHueOverride = nil
                configuration.accentSaturationOverride = nil
                configuration.accentBrightnessOverride = nil
                generatedModeLabel = nil
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
