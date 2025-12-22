//
//  WallpaperRendererFactory.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI

/// Factory for creating the appropriate view for a wallpaper based on its renderer type.
public enum WallpaperRendererFactory {
    @ViewBuilder
    public static func makeView(for wallpaper: LoadedWallpaper) -> some View {
        switch wallpaper.manifest.renderer.type {
        case .stitchable:
            // Use MTKView-based renderer if fragmentFunction is specified (eliminates CPU overhead)
            if wallpaper.manifest.renderer.fragmentFunction != nil {
                StitchableMetalView(wallpaper: wallpaper)
            } else {
                StitchableWallpaperView(wallpaper: wallpaper)
            }

        case .rawMetal:
            RawMetalWallpaperView(wallpaper: wallpaper, directiveStore: wallpaper.directiveStore)

        case .composite:
            CompositeWallpaperView(wallpaper: wallpaper)

        case .swiftUI:
            SwiftUIWallpaperView(wallpaper: wallpaper)

        case .multipass:
            MultiPassMetalView(wallpaper: wallpaper)
        }
    }
}
