//
//  WallpaperSampleApp.swift
//  WallpaperSampleApp
//

import SwiftUI
import Wallpaper

@main
struct WallpaperSampleApp: App {
    var body: some Scene {
        WindowGroup {
            WallpaperListView()
                .preferredColorScheme(.dark)
        }
    }
}
