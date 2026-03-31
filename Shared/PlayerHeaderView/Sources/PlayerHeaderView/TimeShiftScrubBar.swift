//
//  TimeShiftScrubBar.swift
//  PlayerHeaderView
//
//  Scrub bar for time-shifted HLS playback, allowing listeners to seek backwards
//  from the live edge. Shows a slider, time offset label, and a LIVE pill button.
//
//  Created by Jake Bromberg on 03/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Playback

/// A scrub bar that lets listeners seek backwards within a live HLS stream.
///
/// Shown conditionally when `AudioPlayerController.shared.supportsTimeShift` is true
/// and playback is active. The slider ranges from the maximum lookback window (left)
/// to the live edge (right). A "LIVE" pill button snaps back to the live edge.
struct TimeShiftScrubBar: View {
    private static var controller: AudioPlayerController { AudioPlayerController.shared }

    @State private var sliderValue: Double = 0
    @State private var isDragging = false
    @State private var observationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(timeLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Slider(
                    value: $sliderValue,
                    in: 0...max(Self.controller.maxLookbackSeconds, 1)
                ) { editing in
                    isDragging = editing
                    if !editing {
                        Task {
                            let secondsBehind = Self.controller.maxLookbackSeconds - sliderValue
                            await Self.controller.seek(secondsBehindLive: secondsBehind)
                        }
                    }
                }
                .tint(Self.controller.isAtLiveEdge ? .red : .accentColor)

                Button {
                    Task { await Self.controller.seekToLive() }
                } label: {
                    Text("LIVE")
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(Self.controller.isAtLiveEdge ? .white : .secondary)
                        .background(
                            Self.controller.isAtLiveEdge ? Color.red : Color.secondary.opacity(0.2),
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            observationTask = Task {
                guard let stream = Self.controller.timePositionStream else { return }
                for await secondsBehind in stream {
                    guard !isDragging else { continue }
                    sliderValue = Self.controller.maxLookbackSeconds - secondsBehind
                }
            }
        }
        .onDisappear {
            observationTask?.cancel()
        }
    }

    private var timeLabel: String {
        let secondsBehind = Self.controller.maxLookbackSeconds - sliderValue
        if secondsBehind < 1 {
            return "LIVE"
        }
        let totalSeconds = Int(secondsBehind)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "-%d:%02d", minutes, seconds)
    }
}
