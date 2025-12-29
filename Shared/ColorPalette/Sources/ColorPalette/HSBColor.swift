import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Represents a color in HSB (Hue, Saturation, Brightness) color space.
/// Hue is represented as degrees (0-360), saturation and brightness as 0.0-1.0.
public struct HSBColor: Codable, Hashable, Sendable {
    /// Hue value in degrees (0-360).
    public let hue: Double

    /// Saturation value (0.0-1.0).
    public let saturation: Double

    /// Brightness value (0.0-1.0).
    public let brightness: Double

    public init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    /// Rotates the hue by the specified degrees, wrapping around 360.
    public func rotatingHue(by degrees: Double) -> HSBColor {
        var newHue = hue + degrees
        // Normalize to 0-360 range
        while newHue < 0 { newHue += 360 }
        while newHue >= 360 { newHue -= 360 }
        return HSBColor(hue: newHue, saturation: saturation, brightness: brightness)
    }

    #if canImport(UIKit)
    /// Converts to UIColor for use in UIKit contexts.
    public var uiColor: UIColor {
        UIColor(
            hue: hue / 360.0,
            saturation: saturation,
            brightness: brightness,
            alpha: 1.0
        )
    }
    #elseif canImport(AppKit)
    /// Converts to NSColor for use in AppKit contexts.
    public var nsColor: NSColor {
        NSColor(
            hue: hue / 360.0,
            saturation: saturation,
            brightness: brightness,
            alpha: 1.0
        )
    }
    #endif

    /// Converts to SwiftUI Color.
    public var color: Color {
        Color(hue: hue / 360.0, saturation: saturation, brightness: brightness)
    }
}
