//
//  PlayButton.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import SwiftUI
import AppIntents

struct PlayButton: View {
    @AppStorage("isPlaying", store: .wxyc)
    var isPlaying: Bool = false
    
    var body: some View {
        Button(intent: ToggleWXYC()) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .foregroundStyle(.white)
                .font(.caption)
                .fontWeight(.bold)
                .invalidatableContent()
            Text(isPlaying ? "Pause" : "Play")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .invalidatableContent()
        }
    }
}

