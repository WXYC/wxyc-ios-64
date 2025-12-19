//
//  WallpaperConfiguration.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import Foundation
import Observation

/// Main wallpaper configuration - holds the selected wallpaper ID
@Observable
public final class WallpaperConfiguration {
    private let storageKey = "wallpaper.selectedType.v3"
    private let defaultWallpaperID = "WXYCGradientWithNoiseWallpaper"

    public var selectedWallpaperID: String {
        didSet {
            UserDefaults.standard.set(selectedWallpaperID, forKey: storageKey)
        }
    }

    public init() {
        self.selectedWallpaperID = UserDefaults.standard.string(forKey: storageKey) ?? defaultWallpaperID
    }

    public func reset() {
        selectedWallpaperID = defaultWallpaperID
        WallpaperProvider.shared.wallpapers.forEach { $0.reset() }
    }

    /// Clears any corrupted UserDefaults data for wallpaper settings
    public static func nukeLegacyData() {
        UserDefaults.standard.removeObject(forKey: "wallpaper.selectedType.v3")
        UserDefaults.standard.removeObject(forKey: "wallpaper.selectedType")
    }
}
