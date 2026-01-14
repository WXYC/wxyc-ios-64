//
//  WallpaperDetailView.swift
//  Wallpaper
//
//  Detail view for inspecting wallpaper parameters.
//
//  Created by Jake Bromberg on 12/23/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper
import WXUI

struct WallpaperDetailView: View {
    let wallpaper: LoadedTheme

    var body: some View {
        ZStack {
            WallpaperRendererFactory.makeView(for: wallpaper)
                .ignoresSafeArea()
                .navigationTitle(wallpaper.displayName)
                .navigationBarTitleDisplayMode(.inline)
            
            Text(
                """
                WXYC 89.3 FM is the non-commercial student-run radio station of the University of North Carolina at \
                Chapel Hill. We broadcast at 1100 watts from the student union on the UNC campus, 24 hours a day, 365 \
                days a year. Our coverage area encompasses approximately 900 square miles in and around Chapel Hill, \
                Durham, Pittsboro, Apex, and parts of Raleigh.
                """
                )
                .padding()
                .foregroundStyle(.white)
                .preferredColorScheme(wallpaper.manifest.foreground.colorScheme)
                .background {
                    MaterialView(
                        blurRadius: wallpaper.manifest.blurRadius,
                        overlayOpacity: wallpaper.manifest.overlayOpacity,
                        darkProgress: wallpaper.manifest.overlayDarkness
                    )
                }
                .preferredColorScheme(wallpaper.manifest.foreground.colorScheme)
        }
    }
}

#Preview {
    WallpaperDetailView(
        wallpaper: ThemeRegistry.shared.theme(for: "windowlight")!
    )
}
