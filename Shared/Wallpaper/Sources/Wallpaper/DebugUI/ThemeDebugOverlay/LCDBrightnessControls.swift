//
//  LCDBrightnessControls.swift
//  Wallpaper
//
//  Controls for adjusting the LCD visualizer HSB offsets.
//
//  Created by Jake Bromberg on 12/18/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// Controls for adjusting the LCD visualizer HSB offsets.
struct LCDBrightnessControls: View {
    @Bindable var configuration: ThemeConfiguration

    /// The base accent color to apply offsets to (uses effective accent including user overrides)
    private var baseAccent: AccentColor {
        configuration.effectiveAccentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top segments offset
            VStack(alignment: .leading, spacing: 4) {
                Text("Top Segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HSBOffsetPicker(
                    hueOffset: $configuration.lcdMinOffset.hue,
                    saturationOffset: $configuration.lcdMinOffset.saturation,
                    brightnessOffset: $configuration.lcdMinOffset.brightness,
                    baseHue: baseAccent.hue,
                    baseSaturation: baseAccent.saturation,
                    baseBrightness: baseAccent.brightness
                )
            }

            // Bottom segments offset
            VStack(alignment: .leading, spacing: 4) {
                Text("Bottom Segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HSBOffsetPicker(
                    hueOffset: $configuration.lcdMaxOffset.hue,
                    saturationOffset: $configuration.lcdMaxOffset.saturation,
                    brightnessOffset: $configuration.lcdMaxOffset.brightness,
                    baseHue: baseAccent.hue,
                    baseSaturation: baseAccent.saturation,
                    baseBrightness: baseAccent.brightness
                )
            }

            let hasCustomValues =
                configuration.lcdMinOffset != ThemeConfiguration.defaultLCDMinOffset ||
                configuration.lcdMaxOffset != ThemeConfiguration.defaultLCDMaxOffset

            if hasCustomValues {
                Button("Reset to Default") {
                    configuration.lcdMinOffset = ThemeConfiguration.defaultLCDMinOffset
                    configuration.lcdMaxOffset = ThemeConfiguration.defaultLCDMaxOffset
                }
                .font(.caption)
            }
        }
    }
}
#endif
