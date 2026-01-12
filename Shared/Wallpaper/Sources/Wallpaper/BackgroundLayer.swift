//
//  BackgroundLayer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 11/19/25.
//

import SwiftUI

/// A themed background layer that supports smooth material transitions
/// during wallpaper picker scrolling.
///
/// Reads blur radius, overlay opacity, and overlay color from the environment,
/// which are set by `ThemePickerContainer` based on the current theme.
/// During picker transitions, crossfades between the from/to theme's materials.
public struct BackgroundLayer: View {
    let cornerRadius: CGFloat

    @Environment(\.previewThemeTransition) private var themeTransition
    @Environment(\.currentBlurRadius) private var currentBlurRadius
    @Environment(\.currentOverlayOpacity) private var currentOverlayOpacity
    @Environment(\.currentOverlayIsDark) private var currentOverlayIsDark

    public init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if let transition = themeTransition,
           abs(1 - transition.progress) > 0
        {
            // During picker transitions: crossfade between two materials
            ZStack {
                // From material (fades out)
                MaterialView(
                    blurRadius: transition.fromBlurRadius,
                    overlayOpacity: transition.fromOverlayOpacity,
                    isDark: transition.fromOverlayIsDark,
                    cornerRadius: cornerRadius
                )
                .opacity(1 - transition.progress)
                
                // To material (fades in)
                MaterialView(
                    blurRadius: transition.toBlurRadius,
                    overlayOpacity: transition.toOverlayOpacity,
                    isDark: transition.toOverlayIsDark,
                    cornerRadius: cornerRadius
                )
                .opacity(transition.progress)
            }
        } else {
            // Normal mode: single material from environment
            MaterialView(
                blurRadius: currentBlurRadius,
                overlayOpacity: currentOverlayOpacity,
                isDark: currentOverlayIsDark,
                cornerRadius: cornerRadius
            )
        }
    }
}
