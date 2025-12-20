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
            } else if let first = WallpaperRegistry.shared.wallpapers.first {
                WallpaperRendererFactory.makeView(for: first)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }
}
