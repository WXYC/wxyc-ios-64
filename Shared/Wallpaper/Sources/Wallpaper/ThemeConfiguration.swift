//
//  ThemeConfiguration.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import ColorPalette
import Core
import Foundation
import Observation
import SwiftUI

/// Main theme configuration - holds the selected theme ID.
@Observable
@MainActor
public final class ThemeConfiguration {

    // MARK: - LCD Brightness Defaults

    /// Default minimum brightness for LCD segments (applied to top segments).
    /// nonisolated(unsafe) needed for use in EnvironmentKey.defaultValue (nonisolated context).
    public nonisolated(unsafe) static let defaultLCDMinBrightness: Double = 0.90

    /// Default maximum brightness for LCD segments (applied to bottom segments).
    /// nonisolated(unsafe) needed for use in EnvironmentKey.defaultValue (nonisolated context).
    public nonisolated(unsafe) static let defaultLCDMaxBrightness: Double = 1.0

    // MARK: - Storage Keys

    private let storageKey = "wallpaper.selectedType.v3"
    private let defaultThemeID = "wxyc_gradient"

    // MARK: - Per-Theme Storage Keys

    private func accentHueOverrideKey(for themeID: String) -> String {
        "wallpaper.accentHueOverride.\(themeID)"
    }

    private func accentSaturationOverrideKey(for themeID: String) -> String {
        "wallpaper.accentSaturationOverride.\(themeID)"
    }

    private func overlayOpacityOverrideKey(for themeID: String) -> String {
        "wallpaper.overlayOpacityOverride.\(themeID)"
    }

    private func lcdBrightnessOffsetOverrideKey(for themeID: String) -> String {
        "wallpaper.lcdBrightnessOffsetOverride.\(themeID)"
    }

    private func blurRadiusOverrideKey(for themeID: String) -> String {
        "wallpaper.blurRadiusOverride.\(themeID)"
    }

    private func overlayIsDarkOverrideKey(for themeID: String) -> String {
        "wallpaper.overlayIsDarkOverride.\(themeID)"
    }

    private func lcdMinBrightnessKey(for themeID: String) -> String {
        "wallpaper.lcdMinBrightness.\(themeID)"
    }

    private func lcdMaxBrightnessKey(for themeID: String) -> String {
        "wallpaper.lcdMaxBrightness.\(themeID)"
    }

    private func meshGradientPaletteKey(for themeID: String) -> String {
        "wallpaper.meshGradientPalette.\(themeID)"
    }

    // MARK: - Dependencies

    private let registry: any ThemeRegistryProtocol
    private let defaults: UserDefaults

    /// Shared animation start time for all wallpaper renderers.
    /// This ensures picker previews and main view show synchronized animations.
    public private(set) var animationStartTime: Date = Date()

    public var selectedThemeID: String {
        didSet {
            defaults.set(selectedThemeID, forKey: storageKey)
            // Load overrides for the newly selected theme
            loadOverrides(for: selectedThemeID)
        }
    }

    // MARK: - Accent Color Override

    /// Optional hue override (0-360). When nil, uses the theme's default hue.
    /// Stored per-theme so each theme remembers its customizations.
    public var accentHueOverride: Double? {
        didSet {
            let key = accentHueOverrideKey(for: selectedThemeID)
            if let hue = accentHueOverride {
                defaults.set(hue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Optional saturation override (0.0-1.0). When nil, uses the theme's default saturation.
    /// Stored per-theme so each theme remembers its customizations.
    public var accentSaturationOverride: Double? {
        didSet {
            let key = accentSaturationOverrideKey(for: selectedThemeID)
            if let saturation = accentSaturationOverride {
                defaults.set(saturation, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Overlay Opacity Override

    /// Optional overlay opacity override (0.0 to 1.0). When nil, uses the theme's default opacity.
    /// Stored per-theme so each theme remembers its customizations.
    public var overlayOpacityOverride: Double? {
        didSet {
            let key = overlayOpacityOverrideKey(for: selectedThemeID)
            if let opacity = overlayOpacityOverride {
                defaults.set(opacity, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Blur Radius Override

    /// Optional blur radius override (0.0 to 30.0). When nil, uses the theme's default blur radius.
    /// Stored per-theme so each theme remembers its customizations.
    public var blurRadiusOverride: Double? {
        didSet {
            let key = blurRadiusOverrideKey(for: selectedThemeID)
            if let radius = blurRadiusOverride {
                defaults.set(radius, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Returns the effective blur radius, applying any override to the current theme's blur radius.
    public var effectiveBlurRadius: Double {
        if let override = blurRadiusOverride {
            return override
        }
        guard let theme = registry.theme(for: selectedThemeID) else {
            return 8.0
        }
        return theme.manifest.blurRadius
    }

    // MARK: - Overlay Dark/Light Override

    /// Optional dark/light override. When nil, uses the theme's default.
    /// Stored per-theme so each theme remembers its customizations.
    public var overlayIsDarkOverride: Bool? {
        didSet {
            let key = overlayIsDarkOverrideKey(for: selectedThemeID)
            if let isDark = overlayIsDarkOverride {
                defaults.set(isDark, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Returns whether the overlay is dark, applying any override to the current theme's setting.
    public var effectiveOverlayIsDark: Bool {
        if let override = overlayIsDarkOverride {
            return override
        }
        guard let theme = registry.theme(for: selectedThemeID) else {
            return true
        }
        return theme.manifest.overlayIsDark
    }

    /// Returns the effective overlay opacity, applying any override to the current theme's opacity.
    public var effectiveOverlayOpacity: Double {
        if let override = overlayOpacityOverride {
            return override
        }
        guard let theme = registry.theme(for: selectedThemeID) else {
            return 0.0
        }
        return theme.manifest.overlayOpacity
    }

    // MARK: - LCD Brightness Settings

    /// Minimum brightness for LCD segments (applied to top segments). Default: 0.90.
    /// Stored per-theme so each theme remembers its customizations.
    public var lcdMinBrightness: Double = ThemeConfiguration.defaultLCDMinBrightness {
        didSet {
            let key = lcdMinBrightnessKey(for: selectedThemeID)
            defaults.set(lcdMinBrightness, forKey: key)
        }
    }

    /// Maximum brightness for LCD segments (applied to bottom segments). Default: 1.0.
    /// Stored per-theme so each theme remembers its customizations.
    public var lcdMaxBrightness: Double = ThemeConfiguration.defaultLCDMaxBrightness {
        didSet {
            let key = lcdMaxBrightnessKey(for: selectedThemeID)
            defaults.set(lcdMaxBrightness, forKey: key)
        }
    }

    /// Optional LCD brightness offset override (-0.5 to 0.5). When nil, uses the theme's default.
    /// Stored per-theme so each theme remembers its customizations.
    public var lcdBrightnessOffsetOverride: Double? {
        didSet {
            let key = lcdBrightnessOffsetOverrideKey(for: selectedThemeID)
            if let offset = lcdBrightnessOffsetOverride {
                defaults.set(offset, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Returns the effective LCD brightness offset, applying any override to the current theme's offset.
    public var effectiveLCDBrightnessOffset: Double {
        if let override = lcdBrightnessOffsetOverride {
            return override
        }
        guard let theme = registry.theme(for: selectedThemeID) else {
            return 0.0
        }
        return theme.manifest.lcdBrightnessOffset
    }

    // MARK: - Mesh Gradient Palette

    /// The interpolated mesh gradient palette (16 SwiftUI Colors) for the current theme.
    /// Derived from cached HSB colors via MeshGradientPaletteInterpolator.
    public private(set) var meshGradientPalette: [Color]?

    /// Cached dominant HSB colors (3-5) extracted from wallpaper snapshot.
    /// Persisted per-theme to UserDefaults as JSON.
    private var cachedPaletteHSBColors: [HSBColor]? {
        didSet {
            // Persist to UserDefaults
            let key = meshGradientPaletteKey(for: selectedThemeID)
            if let colors = cachedPaletteHSBColors {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(colors) {
                    defaults.set(data, forKey: key)
                }
            } else {
                defaults.removeObject(forKey: key)
            }

            // Recompute interpolated palette
            if let colors = cachedPaletteHSBColors, !colors.isEmpty {
                let interpolator = MeshGradientPaletteInterpolator()
                meshGradientPalette = interpolator.interpolate(colors)
            } else {
                meshGradientPalette = nil
            }
        }
    }

    /// Extracts and caches the mesh gradient palette from a wallpaper snapshot.
    /// - Parameter snapshot: UIImage snapshot of the current wallpaper.
    public func extractAndCachePalette(from snapshot: Core.Image) {
        let extractor = DominantColorExtractor()
        let colors = extractor.extractDominantColors(from: snapshot, count: 5)
        cachedPaletteHSBColors = colors.isEmpty ? nil : colors
    }

    /// Clears the cached palette for the current theme.
    public func clearCachedPalette() {
        cachedPaletteHSBColors = nil
    }

    /// Returns the effective accent color, applying any overrides to the current theme's accent.
    public var effectiveAccentColor: AccentColor {
        guard let theme = registry.theme(for: selectedThemeID) else {
            return AccentColor(hue: accentHueOverride ?? 0, saturation: accentSaturationOverride ?? 1.0)
        }
        let baseAccent = theme.manifest.accent
        return AccentColor(
            hue: accentHueOverride ?? baseAccent.hue,
            saturation: accentSaturationOverride ?? baseAccent.saturation
        )
    }

    // MARK: - Effective Values for Any Theme

    /// Returns the effective accent color for a given theme ID.
    /// For the selected theme, uses in-memory overrides. For other themes, looks up stored overrides.
    public func effectiveAccentColor(for themeID: String) -> AccentColor {
        if themeID == selectedThemeID {
            return effectiveAccentColor
        }
        guard let theme = registry.theme(for: themeID) else {
            return AccentColor(hue: 0, saturation: 1.0)
        }
        let baseAccent = theme.manifest.accent

        // Look up stored overrides for this theme
        let hueKey = accentHueOverrideKey(for: themeID)
        let satKey = accentSaturationOverrideKey(for: themeID)
        let storedHue = defaults.object(forKey: hueKey) != nil ? defaults.double(forKey: hueKey) : nil
        let storedSat = defaults.object(forKey: satKey) != nil ? defaults.double(forKey: satKey) : nil

        return AccentColor(
            hue: storedHue ?? baseAccent.hue,
            saturation: storedSat ?? baseAccent.saturation
        )
    }

    /// Returns the effective overlay opacity for a given theme ID.
    /// For the selected theme, uses in-memory override. For other themes, looks up stored override.
    public func effectiveOverlayOpacity(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return effectiveOverlayOpacity
        }
        guard let theme = registry.theme(for: themeID) else {
            return 0.0
        }

        // Look up stored override for this theme
        let opacityKey = overlayOpacityOverrideKey(for: themeID)
        if defaults.object(forKey: opacityKey) != nil {
            return defaults.double(forKey: opacityKey)
        }
        return theme.manifest.overlayOpacity
    }

    /// Returns the effective LCD brightness offset for a given theme ID.
    /// For the selected theme, uses in-memory override. For other themes, looks up stored override.
    public func effectiveLCDBrightnessOffset(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return effectiveLCDBrightnessOffset
        }
        guard let theme = registry.theme(for: themeID) else {
            return 0.0
        }

        // Look up stored override for this theme
        let offsetKey = lcdBrightnessOffsetOverrideKey(for: themeID)
        if defaults.object(forKey: offsetKey) != nil {
            return defaults.double(forKey: offsetKey)
        }
        return theme.manifest.lcdBrightnessOffset
    }

    /// Returns the effective blur radius for a given theme ID.
    /// For the selected theme, uses in-memory override. For other themes, looks up stored override.
    public func effectiveBlurRadius(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return effectiveBlurRadius
        }
        guard let theme = registry.theme(for: themeID) else {
            return 8.0
        }

        // Look up stored override for this theme
        let blurKey = blurRadiusOverrideKey(for: themeID)
        if defaults.object(forKey: blurKey) != nil {
            return defaults.double(forKey: blurKey)
        }
        return theme.manifest.blurRadius
    }

    /// Returns whether the overlay is dark for a given theme ID.
    /// For the selected theme, uses in-memory override. For other themes, looks up stored override.
    public func effectiveOverlayIsDark(for themeID: String) -> Bool {
        if themeID == selectedThemeID {
            return effectiveOverlayIsDark
        }
        guard let theme = registry.theme(for: themeID) else {
            return true
        }

        // Look up stored override for this theme
        let isDarkKey = overlayIsDarkOverrideKey(for: themeID)
        if defaults.object(forKey: isDarkKey) != nil {
            return defaults.bool(forKey: isDarkKey)
        }
        return theme.manifest.overlayIsDark
    }

    /// Returns the LCD min brightness for a given theme ID.
    /// For the selected theme, uses in-memory value. For other themes, looks up stored value.
    public func lcdMinBrightness(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return lcdMinBrightness
        }

        // Look up stored value for this theme
        let key = lcdMinBrightnessKey(for: themeID)
        if defaults.object(forKey: key) != nil {
            return defaults.double(forKey: key)
        }
        return Self.defaultLCDMinBrightness
    }

    /// Returns the LCD max brightness for a given theme ID.
    /// For the selected theme, uses in-memory value. For other themes, looks up stored value.
    public func lcdMaxBrightness(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return lcdMaxBrightness
        }

        // Look up stored value for this theme
        let key = lcdMaxBrightnessKey(for: themeID)
        if defaults.object(forKey: key) != nil {
            return defaults.double(forKey: key)
        }
        return Self.defaultLCDMaxBrightness
    }

    // MARK: - Per-Theme Override Loading

    /// Loads overrides for a specific theme from UserDefaults.
    private func loadOverrides(for themeID: String) {
        let hueKey = accentHueOverrideKey(for: themeID)
        accentHueOverride = defaults.object(forKey: hueKey) != nil
            ? defaults.double(forKey: hueKey)
            : nil

        let satKey = accentSaturationOverrideKey(for: themeID)
        accentSaturationOverride = defaults.object(forKey: satKey) != nil
            ? defaults.double(forKey: satKey)
            : nil

        let opacityKey = overlayOpacityOverrideKey(for: themeID)
        overlayOpacityOverride = defaults.object(forKey: opacityKey) != nil
            ? defaults.double(forKey: opacityKey)
            : nil

        let offsetKey = lcdBrightnessOffsetOverrideKey(for: themeID)
        lcdBrightnessOffsetOverride = defaults.object(forKey: offsetKey) != nil
            ? defaults.double(forKey: offsetKey)
            : nil

        let blurKey = blurRadiusOverrideKey(for: themeID)
        blurRadiusOverride = defaults.object(forKey: blurKey) != nil
            ? defaults.double(forKey: blurKey)
            : nil

        let isDarkKey = overlayIsDarkOverrideKey(for: themeID)
        overlayIsDarkOverride = defaults.object(forKey: isDarkKey) != nil
            ? defaults.bool(forKey: isDarkKey)
            : nil

        let minBrightnessKey = lcdMinBrightnessKey(for: themeID)
        lcdMinBrightness = defaults.object(forKey: minBrightnessKey) != nil
            ? defaults.double(forKey: minBrightnessKey)
            : Self.defaultLCDMinBrightness

        let maxBrightnessKey = lcdMaxBrightnessKey(for: themeID)
        lcdMaxBrightness = defaults.object(forKey: maxBrightnessKey) != nil
            ? defaults.double(forKey: maxBrightnessKey)
            : Self.defaultLCDMaxBrightness

        // Load cached mesh gradient palette
        let paletteKey = meshGradientPaletteKey(for: themeID)
        if let data = defaults.data(forKey: paletteKey) {
            let decoder = JSONDecoder()
            if let colors = try? decoder.decode([HSBColor].self, from: data), !colors.isEmpty {
                let interpolator = MeshGradientPaletteInterpolator()
                meshGradientPalette = interpolator.interpolate(colors)
            } else {
                meshGradientPalette = nil
            }
        } else {
            meshGradientPalette = nil
        }
    }

    // MARK: - Initialization

    /// Creates a configuration with injected dependencies.
    /// - Parameters:
    ///   - registry: The theme registry for looking up themes.
    ///   - defaults: The UserDefaults instance for persistence.
    public init(
        registry: any ThemeRegistryProtocol = ThemeRegistry.shared,
        defaults: UserDefaults = .standard
    ) {
        self.registry = registry
        self.defaults = defaults

        let storedID = defaults.string(forKey: storageKey)
        // Map legacy IDs to new IDs
        self.selectedThemeID = Self.mapLegacyID(storedID, using: registry) ?? defaultThemeID

        // Load per-theme overrides for the selected theme (includes brightness settings)
        loadOverrides(for: selectedThemeID)
    }

    public func reset() {
        selectedThemeID = defaultThemeID
        accentHueOverride = nil
        accentSaturationOverride = nil
        overlayOpacityOverride = nil
        blurRadiusOverride = nil
        overlayIsDarkOverride = nil
        lcdMinBrightness = Self.defaultLCDMinBrightness
        lcdMaxBrightness = Self.defaultLCDMaxBrightness
        lcdBrightnessOffsetOverride = nil
        meshGradientPalette = nil
        registry.themes.forEach { $0.parameterStore.reset() }
    }

    /// Clears any corrupted UserDefaults data for theme settings.
    public static func nukeLegacyData(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "wallpaper.selectedType.v3")
        defaults.removeObject(forKey: "wallpaper.selectedType")
    }

    /// Maps legacy wallpaper type IDs to new manifest-based IDs.
    private static func mapLegacyID(
        _ legacyID: String?,
        using registry: any ThemeRegistryProtocol
    ) -> String? {
        guard let legacyID else { return nil }

        // If it's already a new-style ID, return it
        if registry.theme(for: legacyID) != nil {
            return legacyID
        }

        // Map legacy class names to new manifest IDs
        let mapping: [String: String] = [
            "WXYCGradientWithNoiseWallpaper": "wxyc_gradient_noise",
            "WXYCGradientWallpaperImplementation": "wxyc_gradient",
            "WaterTurbulenceWallpaper": "water_turbulence",
            "WaterCausticsWallpaper": "water_caustics",
            "SpiralWallpaper": "spiral",
            "PerspexWebLatticeWallpaper": "perspex_web_lattice"
        ]

        return mapping[legacyID]
    }
}
