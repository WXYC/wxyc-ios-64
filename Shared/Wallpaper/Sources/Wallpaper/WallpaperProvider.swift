//
//  WallpaperProvider.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import Foundation

/// Central registry for all available wallpapers
public final class WallpaperProvider {
    public static let shared = WallpaperProvider()
    
    private(set) public var wallpapers: [any Wallpaper] = []
    
    private init() {
        registerDefaultWallpapers()
    }
    
    public func register(_ wallpaper: any Wallpaper) {
        wallpapers.append(wallpaper)
    }
    
    public func wallpaper(for id: String) -> (any Wallpaper)? {
        wallpapers.first { $0.id == id }
    }
    
    private func registerDefaultWallpapers() {
        register(WXYCGradientWallpaperImplementation())
        register(WXYCGradientWithNoiseWallpaper())
        register(WaterTurbulenceWallpaper())
        register(WaterCausticsWallpaper())
        register(SpiralWallpaper())
    }
}
