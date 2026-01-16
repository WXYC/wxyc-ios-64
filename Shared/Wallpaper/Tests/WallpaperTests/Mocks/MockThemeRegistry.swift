//
//  MockThemeRegistry.swift
//  Wallpaper
//
//  Mock implementation of ThemeRegistryProtocol for testing.
//
//  Created by Jake Bromberg on 01/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
@testable import Wallpaper

/// Mock theme registry for testing ThemeConfiguration and ThemePickerState.
@MainActor
final class MockThemeRegistry: ThemeRegistryProtocol {
    private var loadedThemes: [LoadedTheme]
    private var themesByID: [String: LoadedTheme]

    var themes: [LoadedTheme] { loadedThemes }

    init(themes: [LoadedTheme] = []) {
        self.loadedThemes = themes
        self.themesByID = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })
    }

    func theme(for id: String) -> LoadedTheme? {
        themesByID[id]
    }

    // MARK: - Test Helpers

    /// Creates a mock registry with test themes.
    static func withTestThemes() -> MockThemeRegistry {
        MockThemeRegistry(themes: [
            LoadedTheme(manifest: .testDarkTheme),
            LoadedTheme(manifest: .testLightTheme)
        ])
    }

    /// Creates an empty mock registry.
    static func empty() -> MockThemeRegistry {
        MockThemeRegistry(themes: [])
    }
}

// MARK: - Test Theme Manifests

extension ThemeManifest {
    /// A dark test theme with orange accent and dark overlay.
    @MainActor
    static let testDarkTheme = ThemeManifest(
        id: "test_dark",
        displayName: "Test Dark",
        version: "1.0.0",
        renderer: RendererConfiguration(type: .swiftUI),
        accent: AccentColor(hue: 30, saturation: 0.8),
        material: MaterialConfiguration(
            foreground: .light,
            blurRadius: 8.0,
            overlay: OverlayConfiguration(opacity: 0.15, darkness: 1.0)
        )
    )

    /// A light test theme with blue accent and light overlay.
    @MainActor
    static let testLightTheme = ThemeManifest(
        id: "test_light",
        displayName: "Test Light",
        version: "1.0.0",
        renderer: RendererConfiguration(type: .swiftUI),
        accent: AccentColor(hue: 210, saturation: 0.6),
        material: MaterialConfiguration(
            foreground: .dark,
            blurRadius: 12.0,
            overlay: OverlayConfiguration(opacity: 0.1, darkness: 0.0)
        )
    )
}
