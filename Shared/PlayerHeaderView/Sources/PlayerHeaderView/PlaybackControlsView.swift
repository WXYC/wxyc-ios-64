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
/// The icon, the label, and the action all come from one predicate — whether a
/// play request is standing. Splitting *those* (icon from `isPlaying ||
/// isLoading`, action from `isPlaying`) is what let the button show pause while
/// the tap issued a play, so a listener trying to cancel a stuck start instead
/// re-issued it. See `PlaybackController.isPlaybackRequested`.
///
/// `isPlaying` is a second input on purpose, and feeds nothing but the
/// accessibility *value*. Label and value answer different questions: the label
/// names what the tap will do, the value reports whether audio is actually
/// coming out. They diverge for the whole duration of a start that has not yet
/// produced sound, and that divergence is the point — it is the only signal a
/// listener (or `PlayWXYCIntentUITests`) has that a start succeeded rather than
/// merely being requested. Do not collapse them back into one input.
struct PlaybackControlsView: View {
    var isPlaybackRequested: Bool
    var isPlaying: Bool
    var onPlayTapped: () -> Void

    @Environment(\.themeAppearance) private var appearance

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
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
        .brightness(-appearance.playbackDarkness)
        .opacity(appearance.playbackAlpha)
        .blendMode(appearance.playbackBlendMode)
    }

    var image: Image {
        Image(systemName: "\(isPlaybackRequested ? "pause" : "play").circle.fill")
    }

    /// What the tap will do — the same predicate the icon draws from.
    var accessibilityLabelText: String {
        isPlaybackRequested ? "Pause" : "Play"
    }

    /// Whether audio is actually playing. Deliberately not the predicate above.
    var accessibilityValueText: String {
        isPlaying ? "playing" : "paused"
    }
}
