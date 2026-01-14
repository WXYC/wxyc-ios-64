//
//  WallpaperRendererFactory.swift
//  Wallpaper
//
//  Factory for creating appropriate renderer types.
//
//  Created by Jake Bromberg on 12/19/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

/// Factory for creating the appropriate view for a wallpaper based on its renderer type.
public enum WallpaperRendererFactory {
    @ViewBuilder
    public static func makeView(for theme: LoadedTheme) -> some View {
        switch theme.manifest.renderer.type {
        case .stitchable:
            // Use MTKView-based renderer if fragmentFunction is specified (eliminates CPU overhead)
            if theme.manifest.renderer.fragmentFunction != nil {
                MetalWallpaperView(theme: theme)
            } else {
                StitchableWallpaperView(theme: theme)
            }

        case .rawMetal:
            MetalWallpaperView(theme: theme, directiveStore: theme.directiveStore)

        case .composite:
            CompositeWallpaperView(theme: theme)

        case .swiftUI:
            SwiftUIWallpaperView(theme: theme)
        }
    }
}
