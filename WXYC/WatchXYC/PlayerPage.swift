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
import Logger

struct PlayerPage: View {
    // TODO: Convert to binding
    @State var playlist = PlaylistService.shared {
        willSet {
            Log(.info, "Playlist updated, count: \(newValue.playlist.playcuts.count)")
        }
    }
    @State var artwork: UIImage?
    @State private var elementHeights: CGFloat = 0
    let placeholder: UIImage? = UIImage(named: "logo")
    
    var content: NowPlayingEntry {
        if let item = NowPlayingService.shared.nowPlayingItem {
            return NowPlayingEntry(item)
        } else {
            return NowPlayingEntry(
                artist: " ",
                songTitle: " ",
                artwork: placeholder
            )
        }
    }
    
    // TODO: Wonky. Tidy up.
    func image(for geometry: GeometryProxy) -> some View {
        Group {
            if let artwork = artwork {
                format(image: Image(uiImage: artwork), geometry: geometry)
            } else if let playcut = PlaylistService.shared.playlist.playcuts.first {
                format(image: Image("logo", bundle: .main), geometry: geometry)
                    .task {
                        let artwork = await ArtworkService.shared.getArtwork(for: playcut)
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.artwork = artwork
                        }
                    }
            } else {
                format(image: Image("logo", bundle: .main), geometry: geometry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: geometry.size.height - elementHeights)
    }
    
    func format(image: Image, geometry: GeometryProxy) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .cornerRadius(cornerRadius)
            .frame(maxWidth: .infinity, maxHeight: geometry.size.height - elementHeights)
            .clipped(antialiased: true)
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                VStack {
                    image(for: geometry)

                    Text(content.songTitle)
                        .font(.headline)
                        .foregroundStyle(headlineColor)
                        .background(HeightReader())

                    Text(content.artist)
                        .font(.body)
                        .foregroundStyle(subheadlineColor)
                        .background(HeightReader())

                    #if os(watchOS)
                    // TODO: Maximize tappable target.
                    Button(action: {
                        AVAudioSession.sharedInstance().activate { @MainActor activated, error in
                            if activated {
                                Task { @MainActor in
                                    RadioPlayerController.shared.toggle()
                                }
                            } else {
                                Log(.error, "Failed to activate audio session: \(String(describing: error))")
                            }
                        }
                    }) {
                        Image(systemName: RadioPlayerController.shared.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(20)
                            .frame(width: 20, height: 20)
                    }
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .frame(width: 25, height: 25)
                    .background(HeightReader())
                    #endif
                }
            }
            #if os(tvOS)
            .focusable(true)
            .onPlayPauseCommand {
                RadioPlayerController.shared.toggle()
            }
            #endif
        }
    }
    
    var headlineColor: Color {
#if os(tvOS)
        .gray
#else
        Color.init(white: 1)
#endif
    }
    
    var subheadlineColor: Color {
#if os(tvOS)
        Color.init(white: 0.75)
#else
            .gray
#endif
    }

    var cornerRadius: CGFloat {
        #if os(tvOS)
        30
        #else
        10
        #endif
    }
}

extension View where Body: View {
    var group: Group<Body> {
        Group<Body> { self.body }
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
