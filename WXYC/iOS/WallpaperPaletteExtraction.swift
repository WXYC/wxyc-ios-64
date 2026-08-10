//
//  WallpaperPaletteExtraction.swift
//  WXYC
//
//  Captures the live Metal wallpaper's mesh-gradient palette and caches it into
//  the theme configuration. Hoisted out of `AppLifecycleModifier` so the iOS
//  lifecycle hooks (first-launch `.onAppear`, picker-exit `.onChange` in
//  `WXYCApp`) and the future macOS lifecycle share one implementation of the
//  capture-and-retry timing.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger
import Wallpaper

enum WallpaperPaletteExtraction {
    /// Captures the current wallpaper snapshot and caches its mesh-gradient
    /// palette into `themeConfiguration`. Retries up to 5× (200, 400, 600, 800,
    /// 1000 ms) to absorb renderer init timing.
    ///
    /// Shared by the View-level `.onAppear` (first launch) and the Scene-level
    /// `.onChange(of: themePickerState.isActive)` in `WXYCApp`.
    static func extract(into themeConfiguration: ThemeConfiguration) {
        Task {
            for attempt in 1...5 {
                let delay = 200 * attempt
                try? await Task.sleep(for: .milliseconds(delay))

                if let snapshot = MetalWallpaperRenderer.captureMainSnapshot() {
                    themeConfiguration.extractAndCachePalette(from: snapshot)
                    Log(.info, category: .general, "Extracted wallpaper palette for theme: \(themeConfiguration.selectedThemeID) (attempt \(attempt))")
                    return
                }
            }
            Log(.warning, category: .general, "Failed to capture wallpaper snapshot after 5 attempts")
        }
    }
}
