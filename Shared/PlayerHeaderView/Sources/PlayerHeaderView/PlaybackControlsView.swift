//
//  PlaybackControlsView.swift
//  PlayerHeaderView
//
//  Playback control button view
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper

// MARK: - Playback Controls View

/// A simple play/pause button view
struct PlaybackControlsView: View {
    var isPlaying: Bool
    var isLoading: Bool
    var onPlayTapped: () -> Void

    @Environment(\.themeAppearance) private var appearance

    init(isPlaying: Bool, isLoading: Bool = false, onPlayTapped: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.isLoading = isLoading
        self.onPlayTapped = onPlayTapped
    }

    public var body: some View {
        Button(action: onPlayTapped) {
            image
                .resizable()
                .frame(width: 50, height: 50)
                .padding(.trailing, 4)
                .contentTransition(.symbolEffect)
        }
        .accessibilityIdentifier("playPauseButton")
        .accessibilityValue(isPlaying ? "playing" : "paused")
        .foregroundStyle(.secondary)
        .brightness(-appearance.playbackDarkness)
        .opacity(appearance.playbackAlpha)
        .blendMode(appearance.playbackBlendMode)
    }

    var image: Image {
        Image(systemName: "\((isPlaying || isLoading) ? "pause" : "play").circle.fill")
    }
}
