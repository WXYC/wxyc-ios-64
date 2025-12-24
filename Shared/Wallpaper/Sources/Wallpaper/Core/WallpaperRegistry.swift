//
//  WallpaperRegistry.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import Foundation

/// A loaded wallpaper with its manifest and parameter store.
@Observable
@MainActor
public final class LoadedWallpaper: Identifiable, Sendable {
    public let manifest: WallpaperManifest
    public let parameterStore: ParameterStore
    public let directiveStore: ShaderDirectiveStore

    public nonisolated var id: String { manifest.id }
    public var displayName: String { manifest.displayName }

    init(manifest: WallpaperManifest) {
        self.manifest = manifest
        self.parameterStore = ParameterStore(manifest: manifest)
        self.directiveStore = ShaderDirectiveStore()
    }
}

/// Central registry for discovering and loading wallpapers from bundle resources.
@MainActor
public final class WallpaperRegistry: Sendable {
    public static let shared = WallpaperRegistry()

    private let loadedWallpapers: [LoadedWallpaper]
    private let wallpapersByID: [String: LoadedWallpaper]

    private init() {
        let result = Self.loadAllWallpapers()
        loadedWallpapers = result.wallpapers
        wallpapersByID = result.byID
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

    private static func loadAllWallpapers() -> (wallpapers: [LoadedWallpaper], byID: [String: LoadedWallpaper]) {
        let bundle = Bundle.module
        print("WallpaperRegistry: Loading wallpapers from bundle: \(bundle.bundlePath)")

        // Discover all JSON files in the bundle
        guard let jsonURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            print("WallpaperRegistry: No JSON files found in bundle")
            return (wallpapers: [], byID: [:])
        }

        print("WallpaperRegistry: Found \(jsonURLs.count) JSON files")

        let decoder = JSONDecoder()
        var loadedWallpapers = [LoadedWallpaper]()
        var byID: [String: LoadedWallpaper] = [:]

        for url in jsonURLs {
            do {
                let data = try Data(contentsOf: url)
                let manifest = try decoder.decode(WallpaperManifest.self, from: data)
                let wallpaper = LoadedWallpaper(manifest: manifest)
                loadedWallpapers.append(wallpaper)
                byID[manifest.id] = wallpaper
                print("WallpaperRegistry: Loaded wallpaper '\(manifest.displayName)' from \(url.lastPathComponent)")
            } catch {
                continue
                // Not a valid wallpaper manifest - skip silently
                // (could be other JSON files in the bundle)
            }
        }

        // Sort by display name for consistent ordering
        loadedWallpapers.sort { $0.displayName < $1.displayName }

        print("WallpaperRegistry: Loaded \(loadedWallpapers.count) wallpapers: \(loadedWallpapers.map(\.id))")
        
        return (wallpapers: loadedWallpapers, byID: byID)
    }
}
