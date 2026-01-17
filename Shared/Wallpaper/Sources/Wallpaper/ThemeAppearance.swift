//
//  ThemeAppearance.swift
//  Wallpaper
//
//  Theme appearance configuration (light/dark modes).
//
//  Created by Jake Bromberg on 01/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Lerpable
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
@Lerpable
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

    /// Brightness multiplier for active (lit) LCD segments.
    /// Values above 1.0 make segments brighter; below 1.0 makes them dimmer.
    /// Default is 1.24 for dark mode appearance.
    public var lcdActiveBrightness: Double

    /// The blend mode transition for playback controls.
    ///
    /// Uses `DiscreteTransition` to support crossfade between blend modes
    /// during theme picker scrolling.
    public var playbackBlendMode: DiscreteTransition<BlendMode>

    /// The darkness level for playback controls (0.0 = original color, 1.0 = fully darkened).
    public var playbackDarkness: Double

    /// The alpha/opacity for playback controls (0.0 = transparent, 1.0 = opaque).
    public var playbackAlpha: Double

    /// The blend mode transition for material overlays.
    ///
    /// Uses `DiscreteTransition` to support crossfade between blend modes
    /// during theme picker scrolling.
    public var materialBlendMode: DiscreteTransition<BlendMode>

    public init(
        blurRadius: Double = 8.0,
        overlayOpacity: Double = 0.0,
        darkProgress: CGFloat = 1.0,
        accentColor: AccentColor = AccentColor(hue: 23, saturation: 0.75, brightness: 1.0),
        lcdMinOffset: HSBOffset = .defaultMin,
        lcdMaxOffset: HSBOffset = .defaultMax,
        lcdActiveBrightness: Double = 1.24,
        playbackBlendMode: DiscreteTransition<BlendMode> = DiscreteTransition(PlaybackBlendMode.default.blendMode),
        playbackDarkness: Double = 0.0,
        playbackAlpha: Double = 1.0,
        materialBlendMode: DiscreteTransition<BlendMode> = DiscreteTransition(MaterialBlendMode.default.blendMode)
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.darkProgress = darkProgress
        self.accentColor = accentColor
        self.lcdMinOffset = lcdMinOffset
        self.lcdMaxOffset = lcdMaxOffset
        self.lcdActiveBrightness = lcdActiveBrightness
        self.playbackBlendMode = playbackBlendMode
        self.playbackDarkness = playbackDarkness
        self.playbackAlpha = playbackAlpha
        self.materialBlendMode = materialBlendMode
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
