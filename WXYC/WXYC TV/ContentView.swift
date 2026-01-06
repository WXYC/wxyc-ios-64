//
//  ContentView.swift
//  WXYC TV
//
//  Created by Jake Bromberg on 3/1/25.
//

import SwiftUI
import Playback
import Wallpaper

struct ContentView: View {
    let radioPlayerController: RadioPlayerController
    @State private var themeConfiguration: ThemeConfiguration = {
        let config = ThemeConfiguration()
        config.selectedThemeID = "neon_topology_iso"
        return config
    }()

    var body: some View {
        ZStack {
            WallpaperView(configuration: themeConfiguration)
                .ignoresSafeArea()
            PlayerPage(radioPlayerController: radioPlayerController)
        }
    }
}

#Preview {
    ContentView(radioPlayerController: RadioPlayerController.shared)
}
