//
//  WallpaperDebugControls.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Debug controls for wallpaper settings, intended for use in a Form.
public struct WallpaperDebugControls: View {
    @Bindable var configuration: WallpaperConfiguration

    public init(configuration: WallpaperConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        Section {
            Picker("Wallpaper", selection: $configuration.selectedWallpaperID) {
                ForEach(WallpaperRegistry.shared.wallpapers) { wallpaper in
                    Text(wallpaper.displayName).tag(wallpaper.id)
                }
            }

            if let wallpaper = WallpaperRegistry.shared.wallpaper(for: configuration.selectedWallpaperID),
               !wallpaper.manifest.parameters.isEmpty {
                DisclosureGroup("Parameters") {
                    WallpaperDebugControlsGenerator(wallpaper: wallpaper)
                }
            }

            Button("Reset Wallpaper Settings") {
                configuration.reset()
            }
            .foregroundStyle(.red)

            Button("Nuke Legacy Data") {
                WallpaperConfiguration.nukeLegacyData()
            }
            .foregroundStyle(.red)
        } header: {
            Text("Wallpaper")
        }
    }
}
