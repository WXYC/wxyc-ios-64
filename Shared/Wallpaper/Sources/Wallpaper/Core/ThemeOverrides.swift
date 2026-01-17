//
//  ThemeOverrides.swift
//  Wallpaper
//
//  Container for per-theme override values for accent colors, overlay properties,
//  and LCD segment offsets. Enables bulk operations like export without boilerplate.
//
//  Created by Jake Bromberg on 01/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
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
    /// Material blend mode override.
    public var materialBlendMode: String?

    // LCD segment HSB offsets (applied to accent color)
    public var lcdMinOffset: HSBOffset?
    public var lcdMaxOffset: HSBOffset?
    /// Brightness multiplier for active LCD segments.
    public var lcdActiveBrightness: Double?

    public init(
        accentHue: Double? = nil,
        accentSaturation: Double? = nil,
        accentBrightness: Double? = nil,
        overlayOpacity: Double? = nil,
        blurRadius: Double? = nil,
        overlayDarkness: Double? = nil,
        materialBlendMode: String? = nil,
        lcdMinOffset: HSBOffset? = nil,
        lcdMaxOffset: HSBOffset? = nil,
        lcdActiveBrightness: Double? = nil
    ) {
        self.accentHue = accentHue
        self.accentSaturation = accentSaturation
        self.accentBrightness = accentBrightness
        self.overlayOpacity = overlayOpacity
        self.blurRadius = blurRadius
        self.overlayDarkness = overlayDarkness
        self.materialBlendMode = materialBlendMode
        self.lcdMinOffset = lcdMinOffset
        self.lcdMaxOffset = lcdMaxOffset
        self.lcdActiveBrightness = lcdActiveBrightness
    }

    /// Returns true if all override values are nil.
    public var isEmpty: Bool {
        accentHue == nil &&
        accentSaturation == nil &&
        accentBrightness == nil &&
        overlayOpacity == nil &&
        blurRadius == nil &&
        overlayDarkness == nil &&
        materialBlendMode == nil &&
        lcdMinOffset == nil &&
        lcdMaxOffset == nil &&
        lcdActiveBrightness == nil
    }

    /// Resets all overrides to nil.
    public mutating func reset() {
        self = ThemeOverrides()
    }
}
