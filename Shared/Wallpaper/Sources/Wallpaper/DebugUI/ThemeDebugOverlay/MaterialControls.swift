//
//  MaterialControls.swift
//  Wallpaper
//
//  Controls for adjusting the theme's material properties (blur, darkness, opacity).
//
//  Created by Jake Bromberg on 12/18/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// Controls for adjusting the theme's material properties (blur, darkness, opacity).
struct MaterialControls: View {
    @Bindable var configuration: ThemeConfiguration
    let theme: LoadedTheme

    private var blurRadiusBinding: Binding<Double> {
        Binding(
            get: { configuration.blurRadiusOverride ?? theme.manifest.blurRadius },
            set: { configuration.blurRadiusOverride = $0 }
        )
    }

    private var darknessBinding: Binding<Double> {
        Binding(
            get: { configuration.overlayDarknessOverride ?? theme.manifest.overlayDarkness },
            set: { configuration.overlayDarknessOverride = $0 }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { configuration.overlayOpacityOverride ?? theme.manifest.overlayOpacity },
            set: { configuration.overlayOpacityOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Blur radius slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Blur Radius: \(blurRadiusBinding.wrappedValue, format: .number.precision(.fractionLength(1)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: blurRadiusBinding, in: 0...30)
            }

            Divider()

            // Darkness slider (0 = white, 1 = black)
            VStack(alignment: .leading, spacing: 4) {
                Text("Darkness: \(Int(darknessBinding.wrappedValue * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: darknessBinding, in: 0...1)
            }

            Divider()

            // Opacity slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Opacity: \(Int(opacityBinding.wrappedValue * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: opacityBinding, in: 0...1)
            }

            Divider()

            // Blend mode picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Blend Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Blend Mode", selection: $configuration.materialBlendMode) {
                    ForEach(MaterialBlendMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            // Reset button
            let hasOverrides =
                configuration.blurRadiusOverride != nil ||
                configuration.overlayDarknessOverride != nil ||
                configuration.overlayOpacityOverride != nil

            if hasOverrides {
                Button("Reset to Theme Default") {
                    configuration.blurRadiusOverride = nil
                    configuration.overlayDarknessOverride = nil
                    configuration.overlayOpacityOverride = nil
                }
                .font(.caption)
            }
        }
    }
}
#endif
