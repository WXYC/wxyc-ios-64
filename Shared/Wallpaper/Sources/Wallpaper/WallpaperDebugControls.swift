//
//  WallpaperDebugControls.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Debug controls for wallpaper settings, intended for use in a Form
public struct WallpaperDebugControls: View {
    @Bindable var configuration: WallpaperConfiguration

    public init(configuration: WallpaperConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        Section {
            Picker("Wallpaper", selection: $configuration.selectedWallpaperID) {
                ForEach(WallpaperProvider.shared.wallpapers, id: \.id) { wallpaper in
                    Text(wallpaper.displayName).tag(wallpaper.id)
                }
            }

            if let wallpaper = WallpaperProvider.shared.wallpaper(for: configuration.selectedWallpaperID),
               let controls = wallpaper.makeDebugControls() {
                DisclosureGroup("Parameters") {
                    AnyView(controls)
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
