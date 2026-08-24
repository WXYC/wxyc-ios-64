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
//  The intent is built with `init(togglingFrom:)`, never the bare `init()`:
//  widgets don't resolve app-intent parameters, so an unassigned `value` on
//  this `SetValueIntent` means the system never runs `perform()` — no playback,
//  and (because WidgetKit only guarantees a timeline reload once `perform()`
//  returns) the `.invalidatableContent()` shimmer below runs until `Provider`'s
//  next scheduled entry five minutes later.
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
        Button(intent: WidgetToggleWXYC(togglingFrom: isPlaying)) {
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
