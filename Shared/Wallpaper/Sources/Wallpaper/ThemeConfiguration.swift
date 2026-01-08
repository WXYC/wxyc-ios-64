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
    private let storageKey = "wallpaper.selectedType.v3"
    private let accentHueOverrideKey = "wallpaper.accentHueOverride"
    private let accentSaturationOverrideKey = "wallpaper.accentSaturationOverride"
    private let defaultThemeID = "wxyc_gradient"

    /// Shared animation start time for all wallpaper renderers.
    /// This ensures picker previews and main view show synchronized animations.
    public private(set) var animationStartTime: Date = Date()

    public var selectedThemeID: String {
        didSet {
            UserDefaults.standard.set(selectedThemeID, forKey: storageKey)
        }
    }

    // MARK: - Accent Color Override

    /// Optional hue override (0-360). When nil, uses the theme's default hue.
    public var accentHueOverride: Double? {
        didSet {
            if let hue = accentHueOverride {
                UserDefaults.standard.set(hue, forKey: accentHueOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: accentHueOverrideKey)
            }
        }
    }

    /// Optional saturation override (0.0-1.0). When nil, uses the theme's default saturation.
    public var accentSaturationOverride: Double? {
        didSet {
            if let saturation = accentSaturationOverride {
                UserDefaults.standard.set(saturation, forKey: accentSaturationOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: accentSaturationOverrideKey)
            }
        }
    }

    /// Returns the effective accent color, applying any overrides to the current theme's accent.
    public var effectiveAccentColor: AccentColor {
        guard let theme = ThemeRegistry.shared.theme(for: selectedThemeID) else {
            return AccentColor(hue: accentHueOverride ?? 0, saturation: accentSaturationOverride ?? 1.0)
        }
        let baseAccent = theme.manifest.accent
        return AccentColor(
            hue: accentHueOverride ?? baseAccent.hue,
            saturation: accentSaturationOverride ?? baseAccent.saturation
        )
    }

    public init() {
        let storedID = UserDefaults.standard.string(forKey: storageKey)
        // Map legacy IDs to new IDs
        self.selectedThemeID = Self.mapLegacyID(storedID) ?? defaultThemeID

        // Load accent color overrides
        if UserDefaults.standard.object(forKey: accentHueOverrideKey) != nil {
            self.accentHueOverride = UserDefaults.standard.double(forKey: accentHueOverrideKey)
        }
        if UserDefaults.standard.object(forKey: accentSaturationOverrideKey) != nil {
            self.accentSaturationOverride = UserDefaults.standard.double(forKey: accentSaturationOverrideKey)
        }
    }

    public func reset() {
        selectedThemeID = defaultThemeID
        accentHueOverride = nil
        accentSaturationOverride = nil
        ThemeRegistry.shared.themes.forEach { $0.parameterStore.reset() }
    }

    /// Clears any corrupted UserDefaults data for theme settings.
    public static func nukeLegacyData() {
        UserDefaults.standard.removeObject(forKey: "wallpaper.selectedType.v3")
        UserDefaults.standard.removeObject(forKey: "wallpaper.selectedType")
    }

    /// Maps legacy wallpaper type IDs to new manifest-based IDs.
    private static func mapLegacyID(_ legacyID: String?) -> String? {
        guard let legacyID else { return nil }

        // If it's already a new-style ID, return it
        if ThemeRegistry.shared.theme(for: legacyID) != nil {
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
