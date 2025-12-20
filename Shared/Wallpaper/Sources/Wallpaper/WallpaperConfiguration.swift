//
//  WallpaperConfiguration.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import Foundation
import Observation

/// Main wallpaper configuration - holds the selected wallpaper ID.
@Observable
public final class WallpaperConfiguration {
    private let storageKey = "wallpaper.selectedType.v3"
    private let defaultWallpaperID = "wxyc_gradient_noise"

    public var selectedWallpaperID: String {
        didSet {
            UserDefaults.standard.set(selectedWallpaperID, forKey: storageKey)
        }
    }

    public init() {
        let storedID = UserDefaults.standard.string(forKey: storageKey)
        // Map legacy IDs to new IDs
        self.selectedWallpaperID = Self.mapLegacyID(storedID) ?? defaultWallpaperID
    }

    public func reset() {
        selectedWallpaperID = defaultWallpaperID
        WallpaperRegistry.shared.wallpapers.forEach { $0.parameterStore.reset() }
    }

    /// Clears any corrupted UserDefaults data for wallpaper settings.
    public static func nukeLegacyData() {
        UserDefaults.standard.removeObject(forKey: "wallpaper.selectedType.v3")
        UserDefaults.standard.removeObject(forKey: "wallpaper.selectedType")
    }

    /// Maps legacy wallpaper type IDs to new manifest-based IDs.
    private static func mapLegacyID(_ legacyID: String?) -> String? {
        guard let legacyID else { return nil }

        // If it's already a new-style ID, return it
        if WallpaperRegistry.shared.wallpaper(for: legacyID) != nil {
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
