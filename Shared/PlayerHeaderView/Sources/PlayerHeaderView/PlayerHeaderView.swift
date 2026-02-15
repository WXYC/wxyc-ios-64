//
//  PlayerHeaderView.swift
//  PlayerHeaderView
//
//  Main player header view composing playback controls and visualizer
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AVFoundation
import SwiftUI
import Playback
import PlaybackCore
import Wallpaper
import WXUI

// MARK: - Player Header View

/// A complete player header view with playback controls and visualizer
/// Uses AudioPlayerController.shared singleton for playback control
/// Note: The consuming app must call `AudioPlayerController.shared.play(url:)` to start playback
public struct PlayerHeaderView: View {
    /// Uses the shared singleton controller
    private static var controller: AudioPlayerController { AudioPlayerController.shared }

    @Bindable var visualizer: VisualizerDataSource

    /// 2D matrix tracking historical RMS values per bar
    @State var barHistory: [[Float]]

    /// Callback when debug tap occurs (DEBUG only)
    var onDebugTapped: (() -> Void)?

    public init(
        visualizer: VisualizerDataSource,
        previewValues: [Float]? = nil,
        onDebugTapped: (() -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self.onDebugTapped = onDebugTapped
        if let values = previewValues {
            _barHistory = State(initialValue: values.map { value in
                var history = Array(repeating: Float(0), count: VisualizerConstants.historyLength)
                history[0] = value
                return history
            })
        } else {
            _barHistory = State(initialValue: Array(
                repeating: Array(repeating: 0, count: VisualizerConstants.historyLength),
                count: VisualizerConstants.barAmount
            ))
        }
    }
    
    public var body: some View {
        HStack(alignment: .center) {
            PlaybackControlsView(
                isPlaying: Self.controller.isPlaying,
                isLoading: Self.controller.isLoading
            ) {
                Self.controller.toggle(reason: .headerViewToggle)
            }

            VisualizerTimelineView(
                visualizer: visualizer,
                barHistory: $barHistory,
                onDebugTapped: onDebugTapped
            )
        }
        .padding(12)
        .background { BackgroundLayer() }
        .clipShape(.rect(cornerRadius: 12))
        .onAppear {
            Self.controller.installRenderTap()
            if Self.controller.isPlaying {
                visualizer.startConsuming(stream: Self.controller.audioBufferStream)
            }
        }
        .onDisappear {
            Self.controller.removeRenderTap()
            visualizer.stopConsuming()
        }
        .onChange(of: Self.controller.isPlaying) { _, nowPlaying in
            if nowPlaying {
                visualizer.startConsuming(stream: Self.controller.audioBufferStream)
            } else {
                visualizer.stopConsuming()
            }
        }
        .task {
            #if os(iOS) || os(tvOS)
            visualizer.outputLatency = Self.controller.outputLatency
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                visualizer.outputLatency = Self.controller.outputLatency
            }
            #endif
        }
    }
}


// MARK: - Helper Functions

/// Creates an initial bar history array with optional preview values
func createBarHistory(previewValues: [Float]? = nil) -> [[Float]] {
    if let values = previewValues {
        return values.map { value in
            var history = Array(repeating: Float(0), count: VisualizerConstants.historyLength)
            history[0] = value
            return history
        }
    } else {
        return Array(
            repeating: Array(repeating: 0, count: VisualizerConstants.historyLength),
            count: VisualizerConstants.barAmount
        )
    }
}
