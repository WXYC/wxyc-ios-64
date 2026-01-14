//
//  ThemeAppearance.swift
//  Wallpaper
//
//  Created by Claude on 1/12/26.
//

import SwiftUI

/// A snapshot of all interpolatable theme visual properties.
///
/// This struct consolidates the theme's appearance settings into a single value
/// that can be computed once (with overrides applied) and passed through the
/// environment. During picker transitions, appearances can be interpolated.
///
/// Properties fall into two categories:
/// - **Continuous values** (blur, opacity, colors): Mathematically interpolated
/// - **Discrete values** (blend modes): Use `DiscreteTransition` for crossfade support
public struct ThemeAppearance: Equatable, @unchecked Sendable {
    /// The blur radius for material backgrounds.
    public var blurRadius: Double

    /// The opacity of the overlay tint (0.0 to 1.0).
    public var overlayOpacity: Double

    /// How "dark" the overlay is (0.0 = light/white, 1.0 = dark/black).
    public var darkProgress: CGFloat

    /// The accent color for UI elements.
    public var accentColor: AccentColor

    /// HSB offset for LCD min (top) segments.
    public var lcdMinOffset: HSBOffset

    /// HSB offset for LCD max (bottom) segments.
    public var lcdMaxOffset: HSBOffset

    /// The blend mode transition for playback controls.
    ///
    /// Uses `DiscreteTransition` to support crossfade between blend modes
    /// during theme picker scrolling.
    public var playbackBlendMode: DiscreteTransition<BlendMode>

    /// The darkness level for playback controls (0.0 = original color, 1.0 = fully darkened).
    public var playbackDarkness: Double

    /// The alpha/opacity for playback controls (0.0 = transparent, 1.0 = opaque).
    public var playbackAlpha: Double

    public init(
        blurRadius: Double = 8.0,
        overlayOpacity: Double = 0.0,
        darkProgress: CGFloat = 1.0,
        accentColor: AccentColor = AccentColor(hue: 23, saturation: 0.75, brightness: 1.0),
        lcdMinOffset: HSBOffset = .defaultMin,
        lcdMaxOffset: HSBOffset = .defaultMax,
        playbackBlendMode: DiscreteTransition<BlendMode> = DiscreteTransition(PlaybackBlendMode.default.blendMode),
        playbackDarkness: Double = 0.0,
        playbackAlpha: Double = 1.0
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.darkProgress = darkProgress
        self.accentColor = accentColor
        self.lcdMinOffset = lcdMinOffset
        self.lcdMaxOffset = lcdMaxOffset
        self.playbackBlendMode = playbackBlendMode
        self.playbackDarkness = playbackDarkness
        self.playbackAlpha = playbackAlpha
    }

    /// Creates an interpolated appearance between two appearances.
    ///
    /// Continuous values (blur, opacity, colors) are mathematically interpolated.
    /// Discrete values (blend modes) use `DiscreteTransition` for crossfade support.
    ///
    /// - Parameters:
    ///   - from: The starting appearance.
    ///   - to: The ending appearance.
    ///   - progress: The interpolation progress (0.0 = from, 1.0 = to).
    /// - Returns: An interpolated appearance.
    public static func interpolated(from: ThemeAppearance, to: ThemeAppearance, progress: Double) -> ThemeAppearance {
        ThemeAppearance(
            blurRadius: from.blurRadius + (to.blurRadius - from.blurRadius) * progress,
            overlayOpacity: from.overlayOpacity + (to.overlayOpacity - from.overlayOpacity) * progress,
            darkProgress: from.darkProgress + (to.darkProgress - from.darkProgress) * progress,
            accentColor: from.accentColor.interpolated(to: to.accentColor, progress: progress),
            lcdMinOffset: from.lcdMinOffset.interpolated(to: to.lcdMinOffset, progress: progress),
            lcdMaxOffset: from.lcdMaxOffset.interpolated(to: to.lcdMaxOffset, progress: progress),
            playbackBlendMode: DiscreteTransition(
                from: from.playbackBlendMode.snapped,
                to: to.playbackBlendMode.snapped,
                progress: progress
            ),
            playbackDarkness: from.playbackDarkness + (to.playbackDarkness - from.playbackDarkness) * progress,
            playbackAlpha: from.playbackAlpha + (to.playbackAlpha - from.playbackAlpha) * progress
        )
    }
}

// MARK: - Environment Key

private struct ThemeAppearanceKey: EnvironmentKey {
    static let defaultValue = ThemeAppearance()
}

public extension EnvironmentValues {
    /// The current theme appearance, with overrides and transitions applied.
    var themeAppearance: ThemeAppearance {
        get { self[ThemeAppearanceKey.self] }
        set { self[ThemeAppearanceKey.self] = newValue }
    }
}
