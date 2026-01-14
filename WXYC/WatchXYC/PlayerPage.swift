//
//  PlayerPage.swift
//  WXYC
//
//  Player controls page for watchOS.
//
//  Created by Jake Bromberg on 02/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playlist
#if os(watchOS)
import PlaybackWatchOS
#else
import Playback
#endif
import AppServices
#if canImport(UIKit)
import UIKit
#endif
import AVKit
import AVFAudio
    
struct PlayerPage: View {
    @Environment(\.playlistService) private var playlistService
    @State private var playlist: Playlist = .empty
    @State private var elementHeights: CGFloat = 0
    private let placeholder: UIImage = UIImage(named: "logo")!
    private let playbackController: any PlaybackController

    init(playbackController: any PlaybackController) {
        self.playbackController = playbackController
    }
    
    var content: NowPlayingEntry {
        if let playcut = playlist.playcuts.first {
            return NowPlayingEntry(playcut: playcut)
        } else {
            return NowPlayingEntry(
                artist: " ",
                songTitle: " ",
                artwork: placeholder
            )
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                VStack {
                    Group {
                        if let playcut = playlist.playcuts.first {
                            RemoteImage(playcut: playcut)
                        } else {
                            Image.logo
                        }
                    }
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(cornerRadius)
                    .frame(maxWidth: .infinity, maxHeight: geometry.size.height - elementHeights)
                    .clipped(antialiased: true)

                    Text(content.songTitle)
                        .font(.headline)
                        .foregroundStyle(headlineColor)
                        .fontWeight(.bold)
                        .background(HeightReader())
                        .multilineTextAlignment(.center)

                    Text(content.artist)
                        .font(.body)
                        .foregroundStyle(subheadlineColor)
                        .background(HeightReader())
                        .multilineTextAlignment(.center)

                    #if os(watchOS)
                    // TODO: Maximize tappable target.
                    Button(action: {
                        Task { try playbackController.toggle(reason: "Watch play/pause tapped") }
                    }) {
                        Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
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
                try? playbackController.toggle(reason: "tvOS play/pause command")
            }
            .task {
                try? playbackController.play(reason: "tvOS task")
            }
            #endif
            .task {
                guard let playlistService else { return }
                for await playlist in playlistService.updates() {
                    self.playlist = playlist
                }
            }
        }
    }
    
    var headlineColor: Color {
#if os(tvOS)
        Color.init(white: 0.90)
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
    let artwork: SwiftUI.Image?
    
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

    init(playcut: Playcut) {
        self.artist = playcut.artistName
        self.songTitle = playcut.songTitle
        self.artwork = nil
    }
}

extension SwiftUI.Image {
    static var logo: some View {
        ZStack {
            Rectangle()
                .background(.white)
                .background(.ultraThinMaterial)
                .opacity(0.2)
            Image(ImageResource(name: "logo", bundle: .main))
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(.white)
                .opacity(0.75)
                .blendMode(.colorDodge)
                .scaleEffect(0.85)
        }
        .aspectRatio(contentMode: .fit)
        .cornerRadius(10)
        .clipped()
    }
    
    static var background: some View {
        ZStack {
            Image(ImageResource(name: "background", bundle: .main))
                .resizable()
                .opacity(0.95)
            Rectangle()
                .foregroundStyle(.gray)
                .background(.gray)
                .background(.ultraThickMaterial)
                .opacity(0.18)
                .blendMode(.colorBurn)
                .saturation(0)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    PlayerPage(playbackController: RadioPlayerController.shared)
}
