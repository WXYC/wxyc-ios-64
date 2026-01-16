//
//  BackgroundLayer.swift
//  Wallpaper
//
//  Root background layer compositing wallpaper and overlays.
//
//  Created by Jake Bromberg on 01/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A themed background layer that displays material effects.
///
/// Reads the current theme appearance from the environment, which includes
/// blur radius, overlay opacity, and dark progress.
public struct BackgroundLayer: View {
    let cornerRadius: CGFloat

    @Environment(\.themeAppearance) private var appearance

    public init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let transition = appearance.materialBlendMode

        if transition.isTransitioning {
            ZStack {
                materialView
                    .blendMode(transition.from)
                    .opacity(transition.fromOpacity)

                materialView
                    .blendMode(transition.to)
                    .opacity(transition.toOpacity)
            }
        } else {
            materialView
                .blendMode(transition.snapped)
        }
    }

    private var materialView: some View {
        MaterialView(
            blurRadius: appearance.blurRadius,
            overlayOpacity: appearance.overlayOpacity,
            darkProgress: appearance.darkProgress,
            cornerRadius: cornerRadius
        )
    }
}
