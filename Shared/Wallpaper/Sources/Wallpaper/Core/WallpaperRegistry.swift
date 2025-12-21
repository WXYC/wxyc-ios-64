//
//  WallpaperRegistry.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import Foundation

/// A loaded wallpaper with its manifest and parameter store.
@Observable
public final class LoadedWallpaper: Identifiable {
    public let manifest: WallpaperManifest
    public let parameterStore: ParameterStore

    public var id: String { manifest.id }
    public var displayName: String { manifest.displayName }

    init(manifest: WallpaperManifest) {
        self.manifest = manifest
        self.parameterStore = ParameterStore(manifest: manifest)
    }
}

/// Central registry for discovering and loading wallpapers from bundle resources.
public final class WallpaperRegistry {
    public static let shared = WallpaperRegistry()

    private var loadedWallpapers: [LoadedWallpaper] = []
    private var wallpapersByID: [String: LoadedWallpaper] = [:]

    private init() {
        loadAllWallpapers()
    }

    /// Returns all available wallpapers.
    public var wallpapers: [LoadedWallpaper] {
        loadedWallpapers
    }

    /// Finds a wallpaper by its ID.
    public func wallpaper(for id: String) -> LoadedWallpaper? {
        wallpapersByID[id]
    }

    // MARK: - Discovery

    /// Known manifest file names (SPM flattens resources, so we look for them by name)
    private static let manifestNames = [
        "water_turbulence",
        "water_caustics",
        "wxyc_gradient",
        "plasma",
        "twinkling_tunnel",
        "turbulence",
        "chroma_wave",
        "neon_topology",
        "lamp_4d",
        "glyph_spinner",
        "vaporwave_fern"
    ]

    private func loadAllWallpapers() {
        let bundle = Bundle.module
        print("WallpaperRegistry: Loading wallpapers from bundle: \(bundle.bundlePath)")

        for name in Self.manifestNames {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                print("WallpaperRegistry: Could not find \(name).json in bundle")
                continue
            }
            print("WallpaperRegistry: Found \(name).json at \(url.path)")

            do {
                let data = try Data(contentsOf: url)
                let manifest = try JSONDecoder().decode(WallpaperManifest.self, from: data)
                let wallpaper = LoadedWallpaper(manifest: manifest)
                loadedWallpapers.append(wallpaper)
                wallpapersByID[manifest.id] = wallpaper
            } catch {
                print("WallpaperRegistry: Failed to load \(url.path): \(error)")
            }
        }

        // Sort by display name for consistent ordering
        loadedWallpapers.sort { $0.displayName < $1.displayName }
        print("WallpaperRegistry: Loaded \(loadedWallpapers.count) wallpapers: \(loadedWallpapers.map(\.id))")
    }

    /// Reloads all wallpapers from disk. Useful for development.
    public func reload() {
        loadedWallpapers.removeAll()
        wallpapersByID.removeAll()
        loadAllWallpapers()
    }
}
