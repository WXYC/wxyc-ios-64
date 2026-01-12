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

// MARK: - HSB Offset

/// Represents an HSB offset that can be applied to an accent color.
/// Used for LCD segment color gradients where min (top) and max (bottom) segments
/// can have different color offsets from the base accent color.
public struct HSBOffset: Codable, Sendable, Equatable {
    /// Hue offset in degrees (-180 to 180).
    public var hue: Double

    /// Saturation offset (-1 to 1).
    public var saturation: Double

    /// Brightness offset (-1 to 1).
    public var brightness: Double

    /// No offset - all values are zero.
    public static let zero = HSBOffset(hue: 0, saturation: 0, brightness: 0)

    /// Default offset for LCD min (top) segments.
    /// Slightly darker than max to create a gradient effect.
    public static let defaultMin = HSBOffset(hue: 0, saturation: 0, brightness: -0.10)

    /// Default offset for LCD max (bottom) segments.
    public static let defaultMax = HSBOffset.zero

    public init(hue: Double = 0, saturation: Double = 0, brightness: Double = 0) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    /// Returns true if all offsets are zero.
    public var isZero: Bool {
        hue == 0 && saturation == 0 && brightness == 0
    }

    /// Applies this offset to an accent color, returning the resulting HSB values.
    /// - Parameter accent: The base accent color to offset.
    /// - Returns: A tuple of (hue, saturation, brightness) with offset applied and clamped.
    public func applied(to accent: AccentColor) -> (hue: Double, saturation: Double, brightness: Double) {
        // Hue wraps around (0-360)
        var resultHue = accent.hue + hue
        while resultHue < 0 { resultHue += 360 }
        while resultHue >= 360 { resultHue -= 360 }

        // Saturation and brightness clamp to 0-1
        let resultSaturation = max(0, min(1, accent.saturation + saturation))
        let resultBrightness = max(0, min(1, accent.brightness + brightness))

        return (resultHue, resultSaturation, resultBrightness)
    }

    /// Applies this offset to an accent color and returns a SwiftUI Color.
    /// - Parameter accent: The base accent color to offset.
    /// - Returns: A Color with the offset applied.
    public func color(from accent: AccentColor) -> Color {
        let (h, s, b) = applied(to: accent)
        return Color(hue: h / 360.0, saturation: s, brightness: b)
    }

    /// Linearly interpolates between this offset and another.
    /// - Parameters:
    ///   - other: The target offset to interpolate towards.
    ///   - progress: Progress from 0.0 (self) to 1.0 (other).
    /// - Returns: A new HSBOffset with interpolated values.
    public func interpolated(to other: HSBOffset, progress: Double) -> HSBOffset {
        HSBOffset(
            hue: hue + (other.hue - hue) * progress,
            saturation: saturation + (other.saturation - saturation) * progress,
            brightness: brightness + (other.brightness - brightness) * progress
        )
    }
}

