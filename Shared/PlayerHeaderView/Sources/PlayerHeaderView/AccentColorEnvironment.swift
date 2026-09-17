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

// MARK: - Environment Keys

private struct AccentHueKey: EnvironmentKey {
    /// Default hue: orange (23°), normalized to 0.0-1.0 range
    static let defaultValue: Double = 23.0 / 360.0
}

private struct AccentSaturationKey: EnvironmentKey {
    static let defaultValue: Double = 0.75
}

private struct AccentBrightnessKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

// MARK: - LCD HSB Offset Environment Keys

private struct LCDMinOffsetKey: EnvironmentKey {
    static let defaultValue: HSBOffset = .defaultMin
}

private struct LCDMaxOffsetKey: EnvironmentKey {
    static let defaultValue: HSBOffset = .defaultMax
}

private struct LCDActiveBrightnessKey: EnvironmentKey {
    /// The theme's dark default, read rather than copied: this was the last of
    /// three hardcoded `1.24`s, and the other two now live behind
    /// ``LCDConfiguration/defaultActiveBrightness(for:)``.
    ///
    /// Dark, because that is the scheme the literal always meant — an untuned
    /// light scheme resolves its own arm through the theme and never reaches
    /// this default. A `static let` over a stored literal is still a single
    /// `swift_once` and a load: `EnvironmentKey.defaultValue` is evaluated while
    /// SwiftUI *processes* an `.environment(_:_:)` write, not only on a genuine
    /// miss (wxyc-ios-64#866), so nothing here may grow into real work.
    static let defaultValue: Double = LCDConfiguration.defaultActiveBrightness(for: .dark)
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    /// Hue value for LCD visualizer segments (0.0-1.0, normalized).
    var lcdAccentHue: Double {
        get { self[AccentHueKey.self] }
        set { self[AccentHueKey.self] = newValue }
    }

    /// Saturation value for LCD visualizer segments (0.0-1.0).
    var lcdAccentSaturation: Double {
        get { self[AccentSaturationKey.self] }
        set { self[AccentSaturationKey.self] = newValue }
    }

    /// Accent brightness multiplier for LCD segments.
    var lcdAccentBrightness: Double {
        get { self[AccentBrightnessKey.self] }
        set { self[AccentBrightnessKey.self] = newValue }
    }

    // MARK: - LCD HSB Offsets

    /// HSB offset for LCD min (top) segments.
    var lcdMinOffset: HSBOffset {
        get { self[LCDMinOffsetKey.self] }
        set { self[LCDMinOffsetKey.self] = newValue }
    }

    /// HSB offset for LCD max (bottom) segments.
    var lcdMaxOffset: HSBOffset {
        get { self[LCDMaxOffsetKey.self] }
        set { self[LCDMaxOffsetKey.self] = newValue }
    }

    /// Brightness multiplier for active (lit) LCD segments.
    var lcdActiveBrightness: Double {
        get { self[LCDActiveBrightnessKey.self] }
        set { self[LCDActiveBrightnessKey.self] = newValue }
    }
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
