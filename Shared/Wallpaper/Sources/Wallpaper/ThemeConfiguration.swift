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
    private let defaultThemeID = "wxyc_gradient"

    /// Shared animation start time for all wallpaper renderers.
    /// This ensures picker previews and main view show synchronized animations.
    public private(set) var animationStartTime: Date = Date()

    public var selectedThemeID: String {
        didSet {
            UserDefaults.standard.set(selectedThemeID, forKey: storageKey)
        }
    }

    public init() {
        let storedID = UserDefaults.standard.string(forKey: storageKey)
        // Map legacy IDs to new IDs
        self.selectedThemeID = Self.mapLegacyID(storedID) ?? defaultThemeID
    }

    public func reset() {
        selectedThemeID = defaultThemeID
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
