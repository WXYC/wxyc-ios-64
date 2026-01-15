//
//  RootTabView.swift
//  WXYC
//
//  Root tab navigation for iOS app.
//
//  Created by Jake Bromberg on 11/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playlist
import WXUI

struct RootTabView: View {
    private enum Page {
        case playlist
        case infoDetail
    }

    @State private var selectedPage = Page.playlist
    @State private var selectedPlaycut: PlaycutSelection?

    var body: some View {
        TabView(selection: $selectedPage) {
            PlaylistView(selectedPlaycut: $selectedPlaycut)
                .tag(Page.playlist)

            InfoDetailView()
                .tag(Page.infoDetail)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .ignoresSafeArea(edges: .vertical)
        .safeAreaPadding([.top])
        .overlaySheet(isPresented: Binding(
            get: { selectedPlaycut != nil },
            set: { if !$0 { selectedPlaycut = nil } }
        )) {
            if let selection = selectedPlaycut {
                PlaycutDetailView(playcut: selection.playcut, artwork: selection.artwork)
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.playlistService, PlaylistService())
}
