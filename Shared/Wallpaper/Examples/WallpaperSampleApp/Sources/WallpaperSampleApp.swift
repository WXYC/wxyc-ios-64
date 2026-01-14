//
//  WallpaperSampleApp.swift
//  Wallpaper
//
//  Sample app for wallpaper development and testing.
//
//  Created by Jake Bromberg on 12/23/25.
//  Copyright © 2025 WXYC. All rights reserved.
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
