//
//  RootTabView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playlist

struct RootTabView: View {
    private enum Page {
        case playlist
        case infoDetail
    }

    @State private var selectedPage = Page.playlist
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isWallpaperPickerActive) private var isPickerActive

    var body: some View {
        TabView(selection: $selectedPage) {
            PlaylistView()
                .tag(Page.playlist)

            InfoDetailView()
                .tag(Page.infoDetail)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .ignoresSafeArea(edges: .vertical)
        .safeAreaPadding([.top])
    }
}

#Preview {
    RootTabView()
        .environment(\.playlistService, PlaylistService())
}
