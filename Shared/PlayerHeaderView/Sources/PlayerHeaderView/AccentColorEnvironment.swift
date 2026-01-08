//
//  AccentColorEnvironment.swift
//  PlayerHeaderView
//
//  SwiftUI environment values for LCD visualizer accent color.
//

import SwiftUI

// MARK: - Environment Keys

private struct AccentHueKey: EnvironmentKey {
    /// Default hue: orange (23°), normalized to 0.0-1.0 range
    static let defaultValue: Double = 23.0 / 360.0
}

private struct AccentSaturationKey: EnvironmentKey {
    static let defaultValue: Double = 0.75
}

private struct LCDMinBrightnessKey: EnvironmentKey {
    static let defaultValue: Double = 0.90
}

private struct LCDMaxBrightnessKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
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

    /// Minimum brightness for LCD segments (applied to top segments).
    var lcdMinBrightness: Double {
        get { self[LCDMinBrightnessKey.self] }
        set { self[LCDMinBrightnessKey.self] = newValue }
    }

    /// Maximum brightness for LCD segments (applied to bottom segments).
    var lcdMaxBrightness: Double {
        get { self[LCDMaxBrightnessKey.self] }
        set { self[LCDMaxBrightnessKey.self] = newValue }
    }
}

// MARK: - View Extension

public extension View {
    /// Sets the accent color for LCD visualizer segments.
    /// - Parameters:
    ///   - hue: Hue value (0.0-1.0, normalized). Use `AccentColor.normalizedHue`.
    ///   - saturation: Saturation value (0.0-1.0).
    func lcdAccentColor(hue: Double, saturation: Double) -> some View {
        self
            .environment(\.lcdAccentHue, hue)
            .environment(\.lcdAccentSaturation, saturation)
    }

    /// Sets the brightness range for LCD visualizer segments.
    /// - Parameters:
    ///   - min: Minimum brightness (applied to top segments). Default: 0.90.
    ///   - max: Maximum brightness (applied to bottom segments). Default: 1.0.
    func lcdBrightness(min: Double, max: Double) -> some View {
        self
            .environment(\.lcdMinBrightness, min)
            .environment(\.lcdMaxBrightness, max)
    }
}

