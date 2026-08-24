//
//  PlayButton.swift
//  WXYC
//
//  Play/pause button for widget. Owns its own capsule chrome, so every widget
//  layout (`Header`, `MediumNowPlayingWidgetEntryView`,
//  `SmallNowPlayingWidgetEntryView`) gets the identical red pill without
//  re-applying `.background(Capsule().fill(Color.red)).clipped()` at each call
//  site (issue #771).
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppIntents
import Caching
import SwiftUI
import WXYCIntents

struct PlayButton: View {
    @AppStorage(UserDefaults.isPlayingKey, store: .wxyc)
    var isPlaying: Bool = false

    var body: some View {
        Button(intent: WidgetToggleWXYC()) {
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
        .background(Capsule().fill(Color.red))
        .clipped()
    }
}
