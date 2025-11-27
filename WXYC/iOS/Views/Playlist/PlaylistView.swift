//
//  PlaylistView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import WXUI

struct PlaylistView: View {
    @State private var playlistEntries: [any PlaylistEntry] = []
    @Environment(\.playlistService) private var playlistService
    
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear   // removes bottom line

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some View {
        ZStack {
            Color.clear
            
            ScrollView(showsIndicators: false) {
                PlayerHeaderView()
                
                // Playlist entries
                LazyVStack(spacing: 0) {
                    ForEach(playlistEntries, id: \.id) { entry in
                        playlistRow(for: entry)
                            .padding(.vertical, 8)
                    }
                    
                    // Footer button
                    if !playlistEntries.isEmpty {
                        Text("what the freq?")
                            .fontWeight(.black)
                            .foregroundStyle(.white)
                            .padding(.top, 20)
                            .safeAreaPadding(.bottom)
                    }
                }
            }
            .coordinateSpace(name: "scroll")
        }
        .padding(.horizontal, 12)
        .task {
            guard let playlistService else { return }
            for await playlist in playlistService.updates() {
                self.playlistEntries = playlist.entries
            }
        }
    }
    
    @ViewBuilder
    private func playlistRow(for entry: any PlaylistEntry) -> some View {
        switch entry {
        case let playcut as Playcut:
            PlaycutRowView(playcut: playcut)
            
        case let breakpoint as Breakpoint:
            TextRowView(text: breakpoint.formattedDate)
            
        case _ as Talkset:
            TextRowView(text: "Talkset")
            
        default:
            EmptyView()
        }
    }
}

#Preview {
    PlaylistView()
        .environment(\.radioPlayerController, RadioPlayerController.shared)
        .environment(\.playlistService, PlaylistService())
        .background(WXYCBackground())
}
