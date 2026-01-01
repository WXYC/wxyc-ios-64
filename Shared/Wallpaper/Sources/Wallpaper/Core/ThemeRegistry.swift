//
//  ThemeRegistry.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import Foundation

/// A loaded theme with its manifest and parameter store.
@Observable
@MainActor
public final class LoadedTheme: Identifiable, Sendable {
    public let manifest: ThemeManifest
    public let parameterStore: ParameterStore
    public let directiveStore: ShaderDirectiveStore

    public nonisolated var id: String { manifest.id }
    public var displayName: String { manifest.displayName }

    init(manifest: ThemeManifest) {
        self.manifest = manifest
        self.parameterStore = ParameterStore(manifest: manifest)
        self.directiveStore = ShaderDirectiveStore()
    }
}

/// Type alias for backward compatibility during migration.
@available(*, deprecated, renamed: "LoadedTheme")
public typealias LoadedWallpaper = LoadedTheme

/// Central registry for discovering and loading themes from bundle resources.
@MainActor
public final class ThemeRegistry: Sendable {
    public static let shared = ThemeRegistry()

    private let loadedThemes: [LoadedTheme]
    private let themesByID: [String: LoadedTheme]

    private init() {
        let result = Self.loadAllThemes()
        loadedThemes = result.themes
        themesByID = result.byID
    }

    /// Returns all available themes.
    public var themes: [LoadedTheme] {
        loadedThemes
    }

    /// Finds a theme by its ID.
    public func theme(for id: String) -> LoadedTheme? {
        themesByID[id]
    }

    // MARK: - Discovery

    private static func loadAllThemes() -> (themes: [LoadedTheme], byID: [String: LoadedTheme]) {
        let bundle = Bundle.module
        print("ThemeRegistry: Loading themes from bundle: \(bundle.bundlePath)")

        // Discover all JSON files in the bundle
        guard let jsonURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            print("ThemeRegistry: No JSON files found in bundle")
            return (themes: [], byID: [:])
        }

        print("ThemeRegistry: Found \(jsonURLs.count) JSON files")

        let decoder = JSONDecoder()
        var loadedThemes = [LoadedTheme]()
        var byID: [String: LoadedTheme] = [:]

        for url in jsonURLs {
            do {
                let data = try Data(contentsOf: url)
                let manifest = try decoder.decode(ThemeManifest.self, from: data)
                let theme = LoadedTheme(manifest: manifest)
                loadedThemes.append(theme)
                byID[manifest.id] = theme
                print("ThemeRegistry: Loaded theme '\(manifest.displayName)' from \(url.lastPathComponent)")
            } catch {
                continue
                // Not a valid theme manifest - skip silently
                // (could be other JSON files in the bundle)
            }
        }

        // Sort by display name for consistent ordering
        loadedThemes.sort { $0.displayName < $1.displayName }

        print("ThemeRegistry: Loaded \(loadedThemes.count) themes: \(loadedThemes.map(\.id))")

        return (themes: loadedThemes, byID: byID)
    }
}

/// Type alias for backward compatibility during migration.
@available(*, deprecated, renamed: "ThemeRegistry")
public typealias WallpaperRegistry = ThemeRegistry
