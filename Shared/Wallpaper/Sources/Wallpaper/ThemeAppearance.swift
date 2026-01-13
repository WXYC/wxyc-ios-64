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

    /// The blend mode for playback controls.
    public var playbackBlendMode: BlendMode

    public init(
        blurRadius: Double = 8.0,
        overlayOpacity: Double = 0.0,
        darkProgress: CGFloat = 1.0,
        accentColor: AccentColor = AccentColor(hue: 23, saturation: 0.75, brightness: 1.0),
        lcdMinOffset: HSBOffset = .defaultMin,
        lcdMaxOffset: HSBOffset = .defaultMax,
        playbackBlendMode: BlendMode = PlaybackBlendMode.default.blendMode
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.darkProgress = darkProgress
        self.accentColor = accentColor
        self.lcdMinOffset = lcdMinOffset
        self.lcdMaxOffset = lcdMaxOffset
        self.playbackBlendMode = playbackBlendMode
    }

    /// Creates an interpolated appearance between two appearances.
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
            // Blend mode snaps at midpoint (can't interpolate discrete values)
            playbackBlendMode: progress > 0.5 ? to.playbackBlendMode : from.playbackBlendMode
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
