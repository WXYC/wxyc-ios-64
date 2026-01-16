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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(
                label: "Blur Radius",
                value: overrideBinding(
                    get: configuration.blurRadiusOverride,
                    fallback: theme.manifest.material.blurRadius,
                    set: { configuration.blurRadiusOverride = $0 }
                ),
                range: 0...30,
                format: .decimal(precision: 1)
            )

            Divider()

            LabeledSlider(
                label: "Darkness",
                value: overrideBinding(
                    get: configuration.overlayDarknessOverride,
                    fallback: theme.manifest.material.overlay.darkness,
                    set: { configuration.overlayDarknessOverride = $0 }
                ),
                range: 0...1,
                format: .percentage
            )

            Divider()

            LabeledSlider(
                label: "Opacity",
                value: overrideBinding(
                    get: configuration.overlayOpacityOverride,
                    fallback: theme.manifest.material.overlay.opacity,
                    set: { configuration.overlayOpacityOverride = $0 }
                ),
                range: 0...1,
                format: .percentage
            )

            Divider()

            LabeledPicker(label: "Blend Mode", selection: $configuration.materialBlendMode) {
                ForEach(MaterialBlendMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            ConditionalResetButton(
                hasOverrides: configuration.blurRadiusOverride != nil ||
                              configuration.overlayDarknessOverride != nil ||
                              configuration.overlayOpacityOverride != nil,
                label: "Reset to Theme Default"
            ) {
                configuration.blurRadiusOverride = nil
                configuration.overlayDarknessOverride = nil
                configuration.overlayOpacityOverride = nil
            }
        }
    }
}
#endif
