//
//  WallpaperDetailView.swift
//  WallpaperSampleApp
//

import SwiftUI
import Wallpaper
import WXUI

struct WallpaperDetailView: View {
    let wallpaper: LoadedWallpaper

    var body: some View {
        WallpaperRendererFactory.makeView(for: wallpaper)
            .ignoresSafeArea()
            .navigationTitle(wallpaper.displayName)
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    WallpaperDetailView(
        wallpaper: WallpaperRegistry.shared.wallpaper(for: "chroma_wave")!
    )
}
