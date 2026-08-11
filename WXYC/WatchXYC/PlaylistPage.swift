//
//  PlaylistPage.swift
//  WXYC
//
//  Playlist display page for watchOS.
//
//  Created by Jake Bromberg on 02/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import SwiftUI
import Playlist
import AppServices

struct PlaylistPage: View {
    @State private var timelineItems: [TimelineItem] = []
    @Environment(\.playlistService) private var playlistService
    
    var body: some View {
        ZStack {
            Color.clear
            
            ScrollView {
                // Playlist entries
                LazyVStack(spacing: 0) {
                    ForEach(timelineItems, id: \.id) { item in
                        playlistRow(for: item)
                            .padding(.vertical, 8)
                    }

                    // Footer button
                    if !timelineItems.isEmpty {
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
    private func playlistRow(for item: TimelineItem) -> some View {
        switch item {
        case .playcut(let playcut):
            PlaycutView(playcut: playcut)
                .listRowInsets(EdgeInsets(10))

        case .seam(let seam):
            SeamView(seam: seam)
                .listRowBackground(Color.black)

        case .showMarker:
            // watchOS has never surfaced show markers; keep it that way.
            EmptyView()
        }
    }
    
    @MainActor
    private func observePlaylist() async {
        for await playlist in playlistService.updates() {
            self.timelineItems = playlist.timelineItems
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

struct SeamView: View {
    let seam: Seam

    var body: some View {
        Text(seam.plainLabel)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    PlaylistPage()
        .environment(\.playlistService, .preview)
}
