//
//  MacRootView.swift
//  WXYC
//
//  Root navigation view for the macOS app using NavigationSplitView. The
//  sidebar shows the player header and playlist, while the detail pane
//  displays track information for the selected playcut.
//
//  Created by Jake Bromberg on 03/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Playlist
import Wallpaper

struct MacRootView: View {
    @State private var selectedPlaycut: MacPlaycutSelection?

    var body: some View {
        NavigationSplitView {
            MacPlaylistSidebar(selectedPlaycut: $selectedPlaycut)
        } detail: {
            if let selection = selectedPlaycut {
                MacPlaycutDetailView(playcut: selection.playcut)
            } else {
                ContentUnavailableView(
                    "Select a track",
                    systemImage: "music.note",
                    description: Text("Choose a track from the playlist to see its details.")
                )
            }
        }
    }
}
