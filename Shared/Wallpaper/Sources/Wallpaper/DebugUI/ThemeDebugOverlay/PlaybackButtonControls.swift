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
            Picker("Blend Mode", selection: $configuration.playbackBlendMode) {
                ForEach(PlaybackBlendMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Darkness")
                    Spacer()
                    Text(configuration.playbackDarkness, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $configuration.playbackDarkness, in: 0...1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Alpha")
                    Spacer()
                    Text(configuration.playbackAlpha, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $configuration.playbackAlpha, in: 0...1)
            }

            Text("Adjusts the blend mode, darkness, and opacity of the play/pause button.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
