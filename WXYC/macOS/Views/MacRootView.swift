//
//  MacRootView.swift
//  WXYC
//
//  Root view for the macOS app showing the player header and scrollable
//  playlist. Selecting a track opens its detail as a sheet.
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
        ZStack {
            MacPlaylistSidebar(selectedPlaycut: $selectedPlaycut)
        }
        .sheet(item: $selectedPlaycut) { selection in
            MacPlaycutDetailView(playcut: selection.playcut)
                .frame(minWidth: 380, minHeight: 500)
        }
    }
}
