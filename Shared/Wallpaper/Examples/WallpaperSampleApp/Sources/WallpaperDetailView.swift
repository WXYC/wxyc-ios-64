//
//  WallpaperDetailView.swift
//  WallpaperSampleApp
//

import SwiftUI
import Wallpaper

struct WallpaperDetailView: View {
    let wallpaper: LoadedWallpaper

    var body: some View {
        WallpaperRendererFactory.makeView(for: wallpaper)
            .ignoresSafeArea()
            .navigationTitle(wallpaper.displayName)
            .navigationBarTitleDisplayMode(.inline)
    }
}
