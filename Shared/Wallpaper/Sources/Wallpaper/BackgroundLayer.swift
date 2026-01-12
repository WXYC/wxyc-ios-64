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
        if let transition = themeTransition {
            // During picker transitions: interpolate properties on a single material
            let progress = transition.progress
            let blurRadius = lerp(
                from: transition.fromBlurRadius,
                to: transition.toBlurRadius,
                progress: progress
            )
            let overlayOpacity = lerp(
                from: transition.fromOverlayOpacity,
                to: transition.toOverlayOpacity,
                progress: progress
            )
            // Interpolate dark progress: 1.0 = dark, 0.0 = light
            let fromDarkProgress: CGFloat = transition.fromOverlayIsDark ? 1.0 : 0.0
            let toDarkProgress: CGFloat = transition.toOverlayIsDark ? 1.0 : 0.0
            let darkProgress = lerp(from: fromDarkProgress, to: toDarkProgress, progress: progress)

            MaterialView(
                blurRadius: blurRadius,
                overlayOpacity: overlayOpacity,
                darkProgress: darkProgress,
                cornerRadius: cornerRadius
            )
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

    private func lerp(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }
}
