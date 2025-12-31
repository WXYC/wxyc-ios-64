//
//  WallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Main wallpaper view that switches between different wallpaper types.
public struct WallpaperView: View {
    @Bindable var configuration: WallpaperConfiguration

    public init(configuration: WallpaperConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        Group {
            if let wallpaper = WallpaperRegistry.shared.wallpaper(for: configuration.selectedWallpaperID) {
                WallpaperRendererFactory.makeView(for: wallpaper)
                    .id(wallpaper.id)
            } else if let first = WallpaperRegistry.shared.wallpapers.first {
                WallpaperRendererFactory.makeView(for: first)
                    .id(first.id)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .environment(\.wallpaperAnimationStartTime, configuration.animationStartTime)
        .ignoresSafeArea()
    }
}
