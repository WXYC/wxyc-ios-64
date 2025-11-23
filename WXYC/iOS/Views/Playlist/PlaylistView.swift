//
//  PlaylistView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core

struct PlaylistView: View {
    @State private var playlistEntries: [any PlaylistEntry] = []
    @Environment(\.playlistService) private var playlistService
    
    var body: some View {
        ZStack {
            Color.clear
            
            ScrollView {
                PlayerHeaderView()
                
                // Playlist entries
                LazyVStack(spacing: 0) {
                    ForEach(playlistEntries, id: \.id) { entry in
                        playlistRow(for: entry)
                            .padding(.vertical, 8)
                    }
                    
                    // Footer button
                    if !playlistEntries.isEmpty {
                        Button("what the freq?") {
                            // Footer action
                        }
                        .foregroundStyle(.white)
                        .padding(.top, 20)
                    }
                }

            }
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
        .background(
            Image("background")
                .resizable()
                .ignoresSafeArea()
        )
}
