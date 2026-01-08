//
//  ThemeConfiguration.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import Foundation
import Observation

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
    private let lcdMinBrightnessKey = "wallpaper.lcdMinBrightness"
    private let lcdMaxBrightnessKey = "wallpaper.lcdMaxBrightness"
    private let defaultThemeID = "wxyc_gradient"

    // Legacy global keys (for migration)
    private let legacyAccentHueOverrideKey = "wallpaper.accentHueOverride"
    private let legacyAccentSaturationOverrideKey = "wallpaper.accentSaturationOverride"
    private let legacyMaterialTintOverrideKey = "wallpaper.materialTintOverride"
    private let legacyLcdBrightnessOffsetOverrideKey = "wallpaper.lcdBrightnessOffsetOverride"

    // MARK: - Per-Theme Storage Keys

    private func accentHueOverrideKey(for themeID: String) -> String {
        "wallpaper.accentHueOverride.\(themeID)"
    }

    private func accentSaturationOverrideKey(for themeID: String) -> String {
        "wallpaper.accentSaturationOverride.\(themeID)"
    }

    private func materialTintOverrideKey(for themeID: String) -> String {
        "wallpaper.materialTintOverride.\(themeID)"
    }

    private func lcdBrightnessOffsetOverrideKey(for themeID: String) -> String {
        "wallpaper.lcdBrightnessOffsetOverride.\(themeID)"
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

    // MARK: - Material Tint Override

    /// Optional material tint override (-1.0 to 1.0). When nil, uses the theme's default tint.
    /// Positive values lighten (white overlay), negative values darken (black overlay).
    /// Stored per-theme so each theme remembers its customizations.
    public var materialTintOverride: Double? {
        didSet {
            let key = materialTintOverrideKey(for: selectedThemeID)
            if let tint = materialTintOverride {
                defaults.set(tint, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Returns the effective material tint, applying any override to the current theme's tint.
    public var effectiveMaterialTint: Double {
        if let override = materialTintOverride {
            return override
        }
        guard let theme = registry.theme(for: selectedThemeID) else {
            return 0.0
        }
        return theme.manifest.materialTint
    }

    // MARK: - LCD Brightness Settings

    /// Minimum brightness for LCD segments (applied to top segments). Default: 0.90.
    public var lcdMinBrightness: Double = ThemeConfiguration.defaultLCDMinBrightness {
        didSet {
            defaults.set(lcdMinBrightness, forKey: lcdMinBrightnessKey)
        }
    }

    /// Maximum brightness for LCD segments (applied to bottom segments). Default: 1.0.
    public var lcdMaxBrightness: Double = ThemeConfiguration.defaultLCDMaxBrightness {
        didSet {
            defaults.set(lcdMaxBrightness, forKey: lcdMaxBrightnessKey)
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

    /// Returns the effective material tint for a given theme ID.
    /// For the selected theme, uses in-memory override. For other themes, looks up stored override.
    public func effectiveMaterialTint(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return effectiveMaterialTint
        }
        guard let theme = registry.theme(for: themeID) else {
            return 0.0
        }

        // Look up stored override for this theme
        let tintKey = materialTintOverrideKey(for: themeID)
        if defaults.object(forKey: tintKey) != nil {
            return defaults.double(forKey: tintKey)
        }
        return theme.manifest.materialTint
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

    // MARK: - Per-Theme Override Loading

    /// Loads overrides for a specific theme from UserDefaults.
    /// Falls back to legacy global keys if per-theme keys don't exist (migration).
    private func loadOverrides(for themeID: String) {
        let hueKey = accentHueOverrideKey(for: themeID)
        let satKey = accentSaturationOverrideKey(for: themeID)
        let tintKey = materialTintOverrideKey(for: themeID)
        let offsetKey = lcdBrightnessOffsetOverrideKey(for: themeID)

        // Try per-theme keys first, fall back to legacy global keys for migration
        if defaults.object(forKey: hueKey) != nil {
            accentHueOverride = defaults.double(forKey: hueKey)
        } else if defaults.object(forKey: legacyAccentHueOverrideKey) != nil {
            // Migrate legacy value to per-theme storage
            let value = defaults.double(forKey: legacyAccentHueOverrideKey)
            accentHueOverride = value
            defaults.removeObject(forKey: legacyAccentHueOverrideKey)
        } else {
            accentHueOverride = nil
        }

        if defaults.object(forKey: satKey) != nil {
            accentSaturationOverride = defaults.double(forKey: satKey)
        } else if defaults.object(forKey: legacyAccentSaturationOverrideKey) != nil {
            let value = defaults.double(forKey: legacyAccentSaturationOverrideKey)
            accentSaturationOverride = value
            defaults.removeObject(forKey: legacyAccentSaturationOverrideKey)
        } else {
            accentSaturationOverride = nil
        }

        if defaults.object(forKey: tintKey) != nil {
            materialTintOverride = defaults.double(forKey: tintKey)
        } else if defaults.object(forKey: legacyMaterialTintOverrideKey) != nil {
            let value = defaults.double(forKey: legacyMaterialTintOverrideKey)
            materialTintOverride = value
            defaults.removeObject(forKey: legacyMaterialTintOverrideKey)
        } else {
            materialTintOverride = nil
        }

        if defaults.object(forKey: offsetKey) != nil {
            lcdBrightnessOffsetOverride = defaults.double(forKey: offsetKey)
        } else if defaults.object(forKey: legacyLcdBrightnessOffsetOverrideKey) != nil {
            let value = defaults.double(forKey: legacyLcdBrightnessOffsetOverrideKey)
            lcdBrightnessOffsetOverride = value
            defaults.removeObject(forKey: legacyLcdBrightnessOffsetOverrideKey)
        } else {
            lcdBrightnessOffsetOverride = nil
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

        // Load LCD brightness settings (these are global, not per-theme)
        if defaults.object(forKey: lcdMinBrightnessKey) != nil {
            self.lcdMinBrightness = defaults.double(forKey: lcdMinBrightnessKey)
        }
        if defaults.object(forKey: lcdMaxBrightnessKey) != nil {
            self.lcdMaxBrightness = defaults.double(forKey: lcdMaxBrightnessKey)
        }

        // Load per-theme overrides for the selected theme
        loadOverrides(for: selectedThemeID)
    }

    public func reset() {
        selectedThemeID = defaultThemeID
        accentHueOverride = nil
        accentSaturationOverride = nil
        materialTintOverride = nil
        lcdMinBrightness = Self.defaultLCDMinBrightness
        lcdMaxBrightness = Self.defaultLCDMaxBrightness
        lcdBrightnessOffsetOverride = nil
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
