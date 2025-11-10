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
    @State private var playlist: Playlist = .empty
    private let playlistService = PlaylistService()

    var body: some View {
        List {
            Section("Recently Played") {
                ForEach(playlist.wrappedEntries) { wrappedEntry in
                    switch wrappedEntry {
                    case .playcut(let playcut):
                        PlaycutView(playcut: playcut)
                            .listRowInsets(EdgeInsets(10))
                    case .breakpoint(let breakpoint):
                        BreakpointView(breakpoint: breakpoint)
                            .listRowBackground(Color.black)
                    case .talkset(_):
                        TalksetView()
                            .background()
                            .listRowBackground(Color.black)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            
            for await playlist in playlistService {
                self.playlist = playlist
            }
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
}
