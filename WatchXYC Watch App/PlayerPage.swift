//
//  PlayerPage.swift
//  WatchXYC Watch App
//
//  Created by Jake Bromberg on 2/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core

struct PlayerPage: View {    
    @State private var nowPlayingItem = NowPlayingService.shared.nowPlayingItem
    @State private var isPlaying = RadioPlayerController.shared.isPlaying {
        didSet {
            print("HI")
        }
    }
    
    var content: NowPlayingEntry {
        if let item = NowPlayingService.shared.nowPlayingItem {
            return NowPlayingEntry(item)
        } else {
            return NowPlayingEntry(
                artist: "WXYC 89.3 FM",
                songTitle: "Chapel Hill, NC",
                artwork: nil
            )
        }
    }
    
    var body: some View {
        VStack {
            // Show the image if available; otherwise a progress indicator.
            if let image = content.artwork {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            } else {
                ProgressView()
                    .frame(width: 80, height: 80)
            }
            Text(content.songTitle)
                .font(.headline)
            Text(content.artist)
                .font(.body)
            Button(action: {
                RadioPlayerController.shared.toggle()
            }) {
                Image(systemName: RadioPlayerController.shared.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .padding(20)
            }
            .background(Color.accentColor)
            .clipShape(Circle())
            .shadow(radius: 5)

        }
        .padding()
    }
}

struct NowPlayingEntry {
    let artist: String
    let songTitle: String
    let artwork: Image?
    
    init(artist: String, songTitle: String, artwork: UIImage?) {
        self.artist = artist
        self.songTitle = songTitle
        if let artwork {
            self.artwork = Image(uiImage: artwork)
        } else {
            self.artwork = nil
        }
    }
    
    init(_ nowPlayingItem: NowPlayingItem) {
        self.artist = nowPlayingItem.playcut.artistName
        self.songTitle = nowPlayingItem.playcut.songTitle
        if let artwork = nowPlayingItem.artwork {
            self.artwork = Image(uiImage: artwork)
        } else {
            self.artwork = nil
        }
    }
}
