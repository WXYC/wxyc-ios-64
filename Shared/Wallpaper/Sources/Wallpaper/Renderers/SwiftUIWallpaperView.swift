//
//  SwiftUIWallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI
import WXUI

/// View for pure SwiftUI wallpapers (no shaders).
public struct SwiftUIWallpaperView: View {
    let wallpaper: LoadedWallpaper

    public init(wallpaper: LoadedWallpaper) {
        self.wallpaper = wallpaper
    }

    public var body: some View {
        // Currently only supports WXYC gradient
        Rectangle()
            .fill(WXYCGradient())
            .ignoresSafeArea()
    }
}
