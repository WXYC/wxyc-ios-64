//
//  PlaybackButtonControls.swift
//  Wallpaper
//
//  Controls for adjusting the playback button appearance.
//
//  Created by Jake Bromberg on 12/18/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// Controls for adjusting the playback button appearance.
struct PlaybackButtonControls: View {
    @Bindable var configuration: ThemeConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledPicker(label: "Blend Mode", selection: $configuration.playbackBlendMode) {
                ForEach(PlaybackBlendMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            LabeledSlider(
                label: "Darkness",
                value: $configuration.playbackDarkness,
                range: 0...1,
                format: .percentage
            )

            LabeledSlider(
                label: "Alpha",
                value: $configuration.playbackAlpha,
                range: 0...1,
                format: .percentage
            )

            Text("Adjusts the blend mode, darkness, and opacity of the play/pause button.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
