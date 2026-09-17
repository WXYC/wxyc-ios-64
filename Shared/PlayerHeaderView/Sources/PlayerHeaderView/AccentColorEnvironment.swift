//
//  AccentColorEnvironment.swift
//  PlayerHeaderView
//
//  SwiftUI environment values for LCD visualizer accent color.
//
//  Created by Jake Bromberg on 01/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import WallpaperTheme

// MARK: - Missing-injection fallback

/// What `\.lcdActiveBrightness` resolves to when nothing was injected: the
/// theme's dark default, read rather than copied. This was the last of three
/// hardcoded `1.24`s, and the other two now live behind
/// ``LCDConfiguration/defaultActiveBrightness(for:)``.
///
/// Dark, because that is the scheme the literal always meant — an untuned light
/// scheme resolves its own arm through the theme and never reaches this
/// default.
///
/// Hoisted to a `static let` rather than written inline in the `@Entry` default
/// below, because `@Entry` emits a *computed* `defaultValue`: the expression it
/// is handed runs on every lookup that misses, where this constant runs once per
/// process. And a miss is not the only trigger — SwiftUI evaluates `defaultValue`
/// while it *processes* an `.environment(_:_:)` write too (wxyc-ios-64#866), so
/// the expression also runs on every launch that injects correctly. The call
/// this wraps is a pure ternary over two literals and would survive being
/// re-run; naming it keeps that true by construction rather than by inspection,
/// so nothing here can quietly grow into real work.
private enum LCDActiveBrightnessDefault {
    static let dark: Double = LCDConfiguration.defaultActiveBrightness(for: .dark)
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    /// Hue value for LCD visualizer segments (0.0-1.0, normalized).
    ///
    /// Defaults to orange (23°), normalized to the 0.0-1.0 range.
    @Entry var lcdAccentHue: Double = 23.0 / 360.0

    /// Saturation value for LCD visualizer segments (0.0-1.0).
    @Entry var lcdAccentSaturation: Double = 0.75

    /// Accent brightness multiplier for LCD segments.
    @Entry var lcdAccentBrightness: Double = 1.0

    // MARK: - LCD HSB Offsets

    /// HSB offset for LCD min (top) segments.
    @Entry var lcdMinOffset: HSBOffset = .defaultMin

    /// HSB offset for LCD max (bottom) segments.
    @Entry var lcdMaxOffset: HSBOffset = .defaultMax

    /// Brightness multiplier for active (lit) LCD segments.
    @Entry var lcdActiveBrightness: Double = LCDActiveBrightnessDefault.dark
}

// MARK: - View Extension

public extension View {
    /// Sets the accent color for LCD visualizer segments from an AccentColor.
    /// - Parameter color: The accent color containing hue (0-360), saturation (0-1), and brightness.
    func lcdAccentColor(_ color: AccentColor) -> some View {
        self
            .environment(\.lcdAccentHue, color.normalizedHue)
            .environment(\.lcdAccentSaturation, color.saturation)
            .environment(\.lcdAccentBrightness, color.brightness)
    }

    /// Sets the HSB offsets for LCD visualizer segments.
    /// - Parameters:
    ///   - min: HSB offset for top segments.
    ///   - max: HSB offset for bottom segments.
    func lcdHSBOffsets(min: HSBOffset, max: HSBOffset) -> some View {
        self
            .environment(\.lcdMinOffset, min)
            .environment(\.lcdMaxOffset, max)
    }

    /// Sets the brightness multiplier for active (lit) LCD segments.
    /// - Parameter brightness: Values above 1.0 make segments brighter; below 1.0 makes them dimmer.
    func lcdActiveBrightness(_ brightness: Double) -> some View {
        self.environment(\.lcdActiveBrightness, brightness)
    }
}
