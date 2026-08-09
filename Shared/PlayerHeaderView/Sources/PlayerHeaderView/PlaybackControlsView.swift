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
import WallpaperTheme

// MARK: - Playback Controls View

/// A simple play/pause button view
///
/// Renders and acts on a single predicate — whether a play request is
/// standing. Splitting the two (icon from `isPlaying || isLoading`, action
/// from `isPlaying`) is what let the button show pause while the tap issued a
/// play, so a listener trying to cancel a stuck start instead re-issued it.
/// See `PlaybackController.isPlaybackRequested`.
struct PlaybackControlsView: View {
    var isPlaybackRequested: Bool
    var onPlayTapped: () -> Void

    @Environment(\.themeAppearance) private var appearance

    init(isPlaybackRequested: Bool, onPlayTapped: @escaping () -> Void) {
        self.isPlaybackRequested = isPlaybackRequested
        self.onPlayTapped = onPlayTapped
    }

    public var body: some View {
        Button(action: onPlayTapped) {
            image
                .resizable()
                .frame(width: 50, height: 50)
                .padding(.trailing, 4)
                .contentTransition(.symbolEffect)
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("playPauseButton")
        .accessibilityValue(isPlaybackRequested ? "playing" : "paused")
        .brightness(-appearance.playbackDarkness)
        .opacity(appearance.playbackAlpha)
        .blendMode(appearance.playbackBlendMode)
    }

    var image: Image {
        Image(systemName: "\(isPlaybackRequested ? "pause" : "play").circle.fill")
    }
}
