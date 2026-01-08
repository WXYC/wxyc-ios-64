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
    public nonisolated(unsafe) static let defaultLCDMinBrightness: Double = 0.90

    /// Default maximum brightness for LCD segments (applied to bottom segments).
    public nonisolated(unsafe) static let defaultLCDMaxBrightness: Double = 1.0

    // MARK: - Storage Keys

    private let storageKey = "wallpaper.selectedType.v3"
    private let accentHueOverrideKey = "wallpaper.accentHueOverride"
    private let accentSaturationOverrideKey = "wallpaper.accentSaturationOverride"
    private let materialTintOverrideKey = "wallpaper.materialTintOverride"
    private let lcdMinBrightnessKey = "wallpaper.lcdMinBrightness"
    private let lcdMaxBrightnessKey = "wallpaper.lcdMaxBrightness"
    private let lcdBrightnessOffsetOverrideKey = "wallpaper.lcdBrightnessOffsetOverride"
    private let defaultThemeID = "wxyc_gradient"

    // MARK: - Dependencies

    private let registry: any ThemeRegistryProtocol
    private let defaults: UserDefaults

    /// Shared animation start time for all wallpaper renderers.
    /// This ensures picker previews and main view show synchronized animations.
    public private(set) var animationStartTime: Date = Date()

    public var selectedThemeID: String {
        didSet {
            defaults.set(selectedThemeID, forKey: storageKey)
        }
    }

    // MARK: - Accent Color Override

    /// Optional hue override (0-360). When nil, uses the theme's default hue.
    public var accentHueOverride: Double? {
        didSet {
            if let hue = accentHueOverride {
                defaults.set(hue, forKey: accentHueOverrideKey)
            } else {
                defaults.removeObject(forKey: accentHueOverrideKey)
            }
        }
    }

    /// Optional saturation override (0.0-1.0). When nil, uses the theme's default saturation.
    public var accentSaturationOverride: Double? {
        didSet {
            if let saturation = accentSaturationOverride {
                defaults.set(saturation, forKey: accentSaturationOverrideKey)
            } else {
                defaults.removeObject(forKey: accentSaturationOverrideKey)
            }
        }
    }

    // MARK: - Material Tint Override

    /// Optional material tint override (-1.0 to 1.0). When nil, uses the theme's default tint.
    /// Positive values lighten (white overlay), negative values darken (black overlay).
    public var materialTintOverride: Double? {
        didSet {
            if let tint = materialTintOverride {
                defaults.set(tint, forKey: materialTintOverrideKey)
            } else {
                defaults.removeObject(forKey: materialTintOverrideKey)
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
    public var lcdBrightnessOffsetOverride: Double? {
        didSet {
            if let offset = lcdBrightnessOffsetOverride {
                defaults.set(offset, forKey: lcdBrightnessOffsetOverrideKey)
            } else {
                defaults.removeObject(forKey: lcdBrightnessOffsetOverrideKey)
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

        // Load accent color overrides
        if defaults.object(forKey: accentHueOverrideKey) != nil {
            self.accentHueOverride = defaults.double(forKey: accentHueOverrideKey)
        }
        if defaults.object(forKey: accentSaturationOverrideKey) != nil {
            self.accentSaturationOverride = defaults.double(forKey: accentSaturationOverrideKey)
        }
        if defaults.object(forKey: materialTintOverrideKey) != nil {
            self.materialTintOverride = defaults.double(forKey: materialTintOverrideKey)
        }

        // Load LCD brightness settings
        if defaults.object(forKey: lcdMinBrightnessKey) != nil {
            self.lcdMinBrightness = defaults.double(forKey: lcdMinBrightnessKey)
        }
        if defaults.object(forKey: lcdMaxBrightnessKey) != nil {
            self.lcdMaxBrightness = defaults.double(forKey: lcdMaxBrightnessKey)
        }
        if defaults.object(forKey: lcdBrightnessOffsetOverrideKey) != nil {
            self.lcdBrightnessOffsetOverride = defaults.double(forKey: lcdBrightnessOffsetOverrideKey)
        }
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
