//
//  BackgroundLayer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 11/19/25.
//

import SwiftUI

/// A themed background layer that supports smooth material and tint transitions
/// during wallpaper picker scrolling.
///
/// Reads material and tint from the environment, which are set by `ThemePickerContainer`
/// based on the current theme. During picker transitions, crossfades between the
/// from/to theme's materials and tints.
public struct BackgroundLayer: View {
    let cornerRadius: CGFloat

    @Environment(\.previewThemeTransition) private var themeTransition
    @Environment(\.currentMaterial) private var currentMaterial
    @Environment(\.currentMaterialTint) private var currentMaterialTint

    public init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if let transition = themeTransition {
            // During picker transitions: crossfade between two materials
            ZStack {
                // From material (fades out)
                materialLayer(
                    material: transition.fromMaterial,
                    tint: transition.fromMaterialTint
                )
                .opacity(1 - transition.progress)

                // To material (fades in)
                materialLayer(
                    material: transition.toMaterial,
                    tint: transition.toMaterialTint
                )
                .opacity(transition.progress)
            }
        } else {
            // Normal mode: single material with tint from environment
            materialLayer(material: currentMaterial, tint: currentMaterialTint)
        }
    }

    @ViewBuilder
    private func materialLayer(material: Material, tint: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(material)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint > 0 ? Color.white : Color.gray)
                    .opacity(abs(tint))
            }
    }
}
