//
//  PlaylistView.swift
//  WXYC
//
//  SwiftUI replacement for PlaylistViewController
//

import SwiftUI
import Core

struct PlaylistView: View {
    @State private var playlistEntries: [any PlaylistEntry] = []
    private let playlistService = PlaylistService()
    
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
            await observePlaylist()
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
    
    @MainActor
    private func observePlaylist() async {
        for await playlist in playlistService {
            self.playlistEntries = playlist.entries
        }
    }
}

#Preview {
    PlaylistView()
        .environment(\.radioPlayerController, RadioPlayerController.shared)
        .background(
            Image("background")
                .resizable()
                .ignoresSafeArea()
        )
}
