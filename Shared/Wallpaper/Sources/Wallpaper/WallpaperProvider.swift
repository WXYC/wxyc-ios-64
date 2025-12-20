//
//  WallpaperProvider.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import Foundation

/// Central registry for all available wallpapers.
///
/// Wallpapers are automatically registered when they use the `@Wallpaper` macro.
/// The macro generates a static registration that runs when any wallpaper instance is created.
public final class WallpaperProvider {
    public static let shared = WallpaperProvider()

    private var registeredTypes: Set<ObjectIdentifier> = []
    private var typeList: [any WallpaperProtocol.Type] = []

    private init() {
        // Force-instantiate each wallpaper type to trigger registration.
        // Each @Wallpaper-annotated class has a static _registered property
        // that runs once per type, adding the type to typeList.
        // This list must be updated when new wallpaper types are added.
        _ = WXYCGradientWallpaperImplementation()
        _ = WXYCGradientWithNoiseWallpaper()
        _ = WaterTurbulenceWallpaper()
        _ = WaterCausticsWallpaper()
        _ = SpiralWallpaper()
        _ = PerspexWebLatticeWallpaper()
    }

    /// Registers a wallpaper type. Called automatically by the `@Wallpaper` macro.
    public func registerType<W: WallpaperProtocol>(_ type: W.Type) {
        let id = ObjectIdentifier(type)
        guard !registeredTypes.contains(id) else { return }
        registeredTypes.insert(id)
        typeList.append(type)
    }

    /// Returns instances of all registered wallpaper types.
    public var wallpapers: [any WallpaperProtocol] {
        typeList.map { $0.init() }
    }

    /// Finds a wallpaper by its ID.
    public func wallpaper(for id: String) -> (any WallpaperProtocol)? {
        wallpapers.first { $0.id == id }
    }
}
