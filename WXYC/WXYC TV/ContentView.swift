//
//  ContentView.swift
//  WXYC
//
//  Main content view for tvOS app.
//
//  Created by Jake Bromberg on 03/02/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playback
import Wallpaper

struct ContentView: View {
    let playbackController: any PlaybackController
    @State private var themeConfiguration: ThemeConfiguration = {
        let config = ThemeConfiguration()
        config.selectedThemeID = "neon_topology_iso"
        return config
    }()

    var body: some View {
        ZStack {
            WallpaperView(configuration: themeConfiguration)
                .ignoresSafeArea()
            PlayerPage(playbackController: playbackController)
        }
    }
}

#Preview {
    ContentView(playbackController: AudioPlayerController.shared)
}
