//
//  WallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Main wallpaper view that switches between different wallpaper types
public struct WallpaperView: View {
    @Bindable var configuration: WallpaperConfiguration

    public init(configuration: WallpaperConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        let _ = print("WallpaperView body: selectedWallpaperID = \(configuration.selectedWallpaperID)")

        Group {
            if let wallpaper = WallpaperProvider.shared.wallpaper(for: configuration.selectedWallpaperID) {
                AnyView(wallpaper.makeView())
            } else {
                // Fallback to first available or empty
                if let first = WallpaperProvider.shared.wallpapers.first {
                    AnyView(first.makeView())
                } else {
                    AnyView(Color.black.ignoresSafeArea())
                }
            }
        }
    }
}
