//
//  ThemeColors.swift
//  Wallpaper
//
//  Theme color configuration types.
//

import SwiftUI

// MARK: - Foreground Style

/// Foreground style for text displayed over themed backgrounds.
public enum ForegroundStyle: String, Codable, Sendable {
    /// Light (white) text - for dark themes.
    case light
    /// Dark (black) text - for light themes.
    case dark

    /// The primary foreground color.
    public var color: Color {
        switch self {
        case .light: .white
        case .dark: .black
        }
    }

    /// The secondary foreground color (reduced opacity).
    public var secondaryColor: Color {
        switch self {
        case .light: .white.opacity(0.7)
        case .dark: .black.opacity(0.6)
        }
    }
}

// MARK: - Accent Color

/// Accent color used for LCD analyzer and header item backgrounds.
/// Uses HSB color model where brightness is computed dynamically by consumers.
public struct AccentColor: Codable, Sendable, Equatable {
    /// Hue value in degrees (0-360).
    public let hue: Double

    /// Saturation value (0.0-1.0).
    public let saturation: Double

    public init(hue: Double, saturation: Double) {
        self.hue = hue
        self.saturation = saturation
    }

    /// Normalized hue for SwiftUI Color (0.0-1.0).
    public var normalizedHue: Double {
        hue / 360.0
    }

    /// Creates a SwiftUI Color with the specified brightness.
    public func color(brightness: Double) -> Color {
        Color(hue: normalizedHue, saturation: saturation, brightness: brightness)
    }
}
