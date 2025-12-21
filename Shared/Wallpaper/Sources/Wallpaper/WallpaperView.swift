//
//  WallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Main wallpaper view that switches between different wallpaper types.
public struct WallpaperView: View {
    @Bindable var configuration: WallpaperConfiguration
    var audioData: AudioData?

    public init(configuration: WallpaperConfiguration, audioData: AudioData? = nil) {
        self.configuration = configuration
        self.audioData = audioData
    }

    public var body: some View {
        Group {
            if let wallpaper = WallpaperRegistry.shared.wallpaper(for: configuration.selectedWallpaperID) {
                WallpaperRendererFactory.makeView(for: wallpaper, audioData: audioData)
                    .id(wallpaper.id)
            } else if let first = WallpaperRegistry.shared.wallpapers.first {
                WallpaperRendererFactory.makeView(for: first, audioData: audioData)
                    .id(first.id)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }
}
