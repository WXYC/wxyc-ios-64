//
//  ThemeOverrides.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 1/11/26.
//

import Foundation

/// Container for per-theme override values.
/// Used for bulk operations like export without per-property boilerplate.
public struct ThemeOverrides: Codable, Sendable, Equatable {
    public var accentHue: Double?
    public var accentSaturation: Double?
    public var accentBrightness: Double?
    public var overlayOpacity: Double?
    public var blurRadius: Double?
    /// Overlay darkness (0.0 = white, 1.0 = black).
    public var overlayDarkness: Double?

    // LCD segment HSB offsets (applied to accent color)
    public var lcdMinOffset: HSBOffset?
    public var lcdMaxOffset: HSBOffset?

    public init(
        accentHue: Double? = nil,
        accentSaturation: Double? = nil,
        accentBrightness: Double? = nil,
        overlayOpacity: Double? = nil,
        blurRadius: Double? = nil,
        overlayDarkness: Double? = nil,
        lcdMinOffset: HSBOffset? = nil,
        lcdMaxOffset: HSBOffset? = nil
    ) {
        self.accentHue = accentHue
        self.accentSaturation = accentSaturation
        self.accentBrightness = accentBrightness
        self.overlayOpacity = overlayOpacity
        self.blurRadius = blurRadius
        self.overlayDarkness = overlayDarkness
        self.lcdMinOffset = lcdMinOffset
        self.lcdMaxOffset = lcdMaxOffset
    }

    /// Returns true if all override values are nil.
    public var isEmpty: Bool {
        accentHue == nil &&
        accentSaturation == nil &&
        accentBrightness == nil &&
        overlayOpacity == nil &&
        blurRadius == nil &&
        overlayDarkness == nil &&
        lcdMinOffset == nil &&
        lcdMaxOffset == nil
    }

    /// Resets all overrides to nil.
    public mutating func reset() {
        self = ThemeOverrides()
    }
}
