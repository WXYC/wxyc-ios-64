//
//  PlaybackControlsView.swift
//  PlayerHeaderView
//
//  Playback control button view
//

import SwiftUI

// MARK: - Playback Controls View

/// A simple play/pause button view
public struct PlaybackControlsView: View {
    public var isPlaying: Bool
    public var isLoading: Bool
    public var onPlayTapped: () -> Void
    
    public init(isPlaying: Bool, isLoading: Bool = false, onPlayTapped: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.isLoading = isLoading
        self.onPlayTapped = onPlayTapped
    }
    
    public var body: some View {
        Button(action: onPlayTapped) {
            Image(systemName: "\(isPlaying ? "pause" : "play").circle.fill")
                .resizable()
                .frame(width: 50, height: 50)
                .padding(.trailing, 4)
                // .symbolEffect(.bounce.up.wholeSymbol, options: .repeat(.continuous), isActive: isLoading)
        }
        .accessibilityIdentifier("playPauseButton")
        .foregroundColor(.secondary)
    }
}

#Preview {
    PlaybackControlsView(isPlaying: false, onPlayTapped: { })
}
