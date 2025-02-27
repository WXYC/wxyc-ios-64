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
    @State var playlist: Playlist = PlaylistService.shared.playlist
    
    var body: some View {
        List {
            Section("Recently Played") {
                ForEach(PlaylistService.shared.playlist.wrappedEntries) { wrappedEntry in
                    switch wrappedEntry {
                    case .playcut(let playcut):
                        PlaycutView(playcut: playcut)
                            .listRowInsets(EdgeInsets(10))
                    case .breakpoint(let breakpoint):
                        BreakpointView(breakpoint: breakpoint)
                            .listRowBackground(Color.black)
                    case .talkset(_):
                        TalksetView()
                            .background(
                            )
                            .listRowBackground(Color.black)
                    }
                }
            }
        }

        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 2.5) {
            RemoteImage(playcut: playcut)
                .cornerRadius(10)
            Text(playcut.songTitle)
                .font(.body)
            Text(playcut.artistName)
                .font(.caption)
        }
    }
}

struct RemoteImage: View {
    let playcut: Playcut
    let placeholder: Image = Image(systemName: "photo")
    @State var artFetcher: AlbumArtworkFetcher
    @State var artwork: UIImage?
    
    init(playcut: Playcut) {
        self.playcut = playcut
        self.artFetcher = AlbumArtworkFetcher(playcut: playcut)
    }

    var body: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 75, height: 75)
            } else {
                placeholder.renderingMode(.original)
            }
        }
        .task {
            artwork = await artFetcher.fetchArtwork()
        }
    }
}

struct AlbumArtworkFetcher {
    let playcut: Playcut
    
    func fetchArtwork() async -> UIImage? {
        await ArtworkService.shared.getArtwork(for: playcut)
    }
}

struct BreakpointView: View {
    let date: String
    
    init(breakpoint: Breakpoint) {
        let timeSince1970 = Double(breakpoint.hour) / 1000.0
        let date = Date(timeIntervalSince1970: timeSince1970)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h a"
        self.date = dateFormatter.string(from: date)
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
