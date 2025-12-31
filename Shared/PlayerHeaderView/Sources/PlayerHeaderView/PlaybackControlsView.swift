//
//  PlaybackControlsView.swift
//  PlayerHeaderView
//
//  Playback control button view
//

import SwiftUI

// MARK: - Playback Controls View

/// A simple play/pause button view
struct PlaybackControlsView: View {
    var isPlaying: Bool
    var isLoading: Bool
    var onPlayTapped: () -> Void
    
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
        .foregroundColor(.secondary)
    }

    var image: Image {
        Image(systemName: "\((isPlaying || isLoading) ? "pause" : "play").circle.fill")
    }
}
