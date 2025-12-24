//
//  WallpaperListView.swift
//  WallpaperSampleApp
//

import SwiftUI
import Wallpaper

struct WallpaperListView: View {
    private let wallpapers = WallpaperRegistry.shared.wallpapers

    var body: some View {
        NavigationStack {
            List(wallpapers) { wallpaper in
                NavigationLink(wallpaper.displayName) {
                    WallpaperDetailView(wallpaper: wallpaper)
                }
            }
            .navigationTitle("Wallpapers")
        }
    }
}

#Preview {
    WallpaperListView()
}
