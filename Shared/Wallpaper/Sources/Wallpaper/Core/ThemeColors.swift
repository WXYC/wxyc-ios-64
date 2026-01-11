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
    
    public var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Accent Color

/// Accent color used for LCD analyzer and header item backgrounds.
/// Uses HSB color model for full color specification.
public struct AccentColor: Codable, Sendable, Equatable {
    /// Hue value in degrees (0-360).
    public let hue: Double

    /// Saturation value (0.0-1.0).
    public let saturation: Double

    /// Brightness multiplier for LCD segments (default 1.0).
    /// Values above 1.0 increase brightness, below 1.0 decrease it.
    public let brightness: Double

    public init(hue: Double, saturation: Double, brightness: Double = 1.0) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    /// Normalized hue for SwiftUI Color (0.0-1.0).
    public var normalizedHue: Double {
        hue / 360.0
    }

    /// Creates a SwiftUI Color with the specified brightness.
    public func color(brightness: Double) -> Color {
        Color(hue: normalizedHue, saturation: saturation, brightness: brightness)
    }

    /// Interpolates between this accent color and another in RGB space.
    /// This avoids the rainbow effect that occurs when linearly interpolating hue values.
    /// - Parameters:
    ///   - other: The target accent color to interpolate towards.
    ///   - progress: Progress from 0.0 (self) to 1.0 (other).
    ///   - referenceBrightness: Brightness value used for RGB conversion (default 0.95).
    /// - Returns: A new AccentColor with interpolated values.
    public func interpolated(to other: AccentColor, progress: Double, referenceBrightness: Double = 0.95) -> AccentColor {
        // Convert both colors to RGB using the reference brightness
        let (r1, g1, b1) = hsbToRGB(h: normalizedHue, s: saturation, b: referenceBrightness)
        let (r2, g2, b2) = hsbToRGB(h: other.normalizedHue, s: other.saturation, b: referenceBrightness)

        // Linearly interpolate RGB components
        let r = r1 + (r2 - r1) * progress
        let g = g1 + (g2 - g1) * progress
        let b = b1 + (b2 - b1) * progress

        // Convert back to HSB
        let (h, s, _) = rgbToHSB(r: r, g: g, b: b)

        // Linearly interpolate brightness
        let interpolatedBrightness = brightness + (other.brightness - brightness) * progress

        return AccentColor(hue: h * 360.0, saturation: s, brightness: interpolatedBrightness)
    }

    // MARK: - Color Space Conversion

    private func hsbToRGB(h: Double, s: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        if s == 0 {
            return (b, b, b)
        }

        let h6 = h * 6.0
        let sector = Int(h6) % 6
        let f = h6 - Double(sector)
        let p = b * (1.0 - s)
        let q = b * (1.0 - s * f)
        let t = b * (1.0 - s * (1.0 - f))

        switch sector {
        case 0: return (b, t, p)
        case 1: return (q, b, p)
        case 2: return (p, b, t)
        case 3: return (p, q, b)
        case 4: return (t, p, b)
        default: return (b, p, q)
        }
    }

    private func rgbToHSB(r: Double, g: Double, b: Double) -> (h: Double, s: Double, b: Double) {
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal

        let brightness = maxVal
        let saturation = maxVal == 0 ? 0 : delta / maxVal

        var hue: Double = 0
        if delta > 0 {
            if maxVal == r {
                hue = (g - b) / delta
                if g < b { hue += 6 }
            } else if maxVal == g {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            hue /= 6
        }

        return (hue, saturation, brightness)
    }
}

