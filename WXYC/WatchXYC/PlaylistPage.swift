//
//  PlaylistPage.swift
//  WatchXYC App
//
//  Created by Jake Bromberg on 2/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import SwiftUI
import Core

struct PlaylistPage: View {
    @State private var playlistEntries: [any PlaylistEntry] = []
    @Environment(\.playlistService) private var playlistService
    
    var body: some View {
        ZStack {
            Color.clear
            
            ScrollView {
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
            PlaycutView(playcut: playcut)
                .listRowInsets(EdgeInsets(10))
            
        case let breakpoint as Breakpoint:
            BreakpointView(breakpoint: breakpoint)
                .listRowBackground(Color.black)
            
        case _ as Talkset:
            TalksetView()
                .background()
                .listRowBackground(Color.black)
            
        default:
            EmptyView()
        }
    }
    
    @MainActor
    private func observePlaylist() async {
        guard let playlistService else { return }
        for await playlist in playlistService.updates() {
            self.playlistEntries = playlist.entries
        }
    }
}

extension EdgeInsets {
    init(_ inset: CGFloat) {
        self.init(top: inset, leading: inset, bottom: inset, trailing: inset)
    }
}

struct PlaycutView: View {
    let playcut: Playcut
    
    init(playcut: Playcut) {
        self.playcut = playcut
        
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            RemoteImage(playcut: playcut)
                .cornerRadius(10)
                .frame(
                    width: 50,
                    height: 50
                )
            
            Text(playcut.songTitle)
                .font(.body)
                .fontWeight(.bold)
            Text(playcut.artistName)
                .font(.caption)
        }
    }
}

struct BreakpointView: View {
    let date: String
    
    init(breakpoint: Breakpoint) {
        self.date = breakpoint.formattedDate
    }
    
    var body: some View {
        Text("\(date)")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct TalksetView: View {
    var body: some View {
        Text("Talkset")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    PlaylistPage()
        .environment(\.playlistService, PlaylistService())
}
