//
//  WallpaperListView.swift
//  Wallpaper
//
//  List view for browsing available wallpapers.
//
//  Created by Jake Bromberg on 12/23/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper

struct WallpaperListView: View {
    private let theme = ThemeRegistry.shared.themes
    @State private var showDebugHUD = false

    var body: some View {
        NavigationStack {
            List(theme) { wallpaper in
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
