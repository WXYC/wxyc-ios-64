//
//  WallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Main wallpaper view that switches between different wallpaper types.
public struct WallpaperView: View {
    @Bindable var configuration: ThemeConfiguration

    public init(configuration: ThemeConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        Group {
            if let theme = configuration.selectedTheme {
                WallpaperRendererFactory.makeView(for: theme)
                    .id(theme.id)
            } else if let first = ThemeRegistry.shared.themes.first {
                WallpaperRendererFactory.makeView(for: first)
                    .id(first.id)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .environment(\.wallpaperAnimationStartTime, configuration.animationStartTime)
        .ignoresSafeArea()
    }
}
