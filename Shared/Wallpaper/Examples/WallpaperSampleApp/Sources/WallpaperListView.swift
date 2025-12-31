//
//  WallpaperListView.swift
//  WallpaperSampleApp
//

import SwiftUI
import Wallpaper

struct WallpaperListView: View {
    private let wallpapers = WallpaperRegistry.shared.wallpapers
    @State private var showDebugHUD = false

    var body: some View {
        NavigationStack {
            List(wallpapers) { wallpaper in
                NavigationLink(wallpaper.displayName) {
                    WallpaperDetailView(wallpaper: wallpaper)
                        .overlay {
                            if showDebugHUD {
                                DebugHUD()
                            }
                        }
                }
            }
            .navigationTitle("Wallpapers")
            .toolbar {
                Toggle("Debug HUD", systemImage: "gauge.with.dots.needle.33percent", isOn: $showDebugHUD)
            }
        }
    }
}

#Preview {
    WallpaperListView()
}
