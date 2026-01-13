//
//  BackgroundLayer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 11/19/25.
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
        MaterialView(
            blurRadius: appearance.blurRadius,
            overlayOpacity: appearance.overlayOpacity,
            darkProgress: appearance.darkProgress,
            cornerRadius: cornerRadius
        )
    }
}
