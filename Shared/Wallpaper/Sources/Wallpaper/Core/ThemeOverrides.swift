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
    public var overlayIsDark: Bool?
    public var lcdMinBrightness: Double?
    public var lcdMaxBrightness: Double?

    public init(
        accentHue: Double? = nil,
        accentSaturation: Double? = nil,
        accentBrightness: Double? = nil,
        overlayOpacity: Double? = nil,
        blurRadius: Double? = nil,
        overlayIsDark: Bool? = nil,
        lcdMinBrightness: Double? = nil,
        lcdMaxBrightness: Double? = nil
    ) {
        self.accentHue = accentHue
        self.accentSaturation = accentSaturation
        self.accentBrightness = accentBrightness
        self.overlayOpacity = overlayOpacity
        self.blurRadius = blurRadius
        self.overlayIsDark = overlayIsDark
        self.lcdMinBrightness = lcdMinBrightness
        self.lcdMaxBrightness = lcdMaxBrightness
    }

    /// Returns true if all override values are nil.
    public var isEmpty: Bool {
        accentHue == nil &&
        accentSaturation == nil &&
        accentBrightness == nil &&
        overlayOpacity == nil &&
        blurRadius == nil &&
        overlayIsDark == nil &&
        lcdMinBrightness == nil &&
        lcdMaxBrightness == nil
    }

    /// Resets all overrides to nil.
    public mutating func reset() {
        self = ThemeOverrides()
    }
}
