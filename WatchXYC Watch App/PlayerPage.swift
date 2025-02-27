//
//  PlayerPage.swift
//  WatchXYC Watch App
//
//  Created by Jake Bromberg on 2/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import UIKit
import AVKit
import AVFAudio

struct PlayerPage: View {
    @State var playlist = PlaylistService.shared.playlist
    let placeholder: Image = Image(ImageResource(name: "logo", bundle: .main))
    @State var artwork: UIImage?
    @State private var elementHeights: CGFloat = 0
    
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
        GeometryReader { geometry in
            VStack {
                if let playcut = PlaylistService.shared.playlist.playcuts.first {
                    RemoteImage(playcut: playcut)
                        .frame(maxWidth: .infinity, maxHeight: geometry.size.height - elementHeights)
                }
                
                VStack {
                    Text(content.songTitle)
                        .font(.headline)
                        .background(HeightReader())

                    Text(content.artist)
                        .font(.body)
                        .background(HeightReader())

                    Button(action: {
                        AVAudioSession.sharedInstance().activate { @MainActor activated, error in
                            RadioPlayerController.shared.toggle()
                        }
                    }) {
                        Image(systemName: RadioPlayerController.shared.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(20)
                            .frame(width: 15, height: 15)
                            .cornerRadius(5)
                    }
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .frame(width: 25, height: 25)
                    .background(HeightReader())
                }
            }
        }
    }
}

// Define a PreferenceKey to collect text heights.
struct TextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Add up heights from multiple text views.
        value += nextValue()
    }
}

// A helper view to measure height.
struct HeightReader: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: TextHeightPreferenceKey.self, value: geo.size.height)
        }
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

#Preview {
    PlayerPage()
}
