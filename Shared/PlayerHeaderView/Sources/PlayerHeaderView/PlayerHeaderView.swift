//
//  PlayerHeaderView.swift
//  PlayerHeaderView
//
//  Main player header view composing playback controls and visualizer
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playback
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
                Self.controller.toggle()
            }

            VisualizerTimelineView(
                visualizer: visualizer,
                barHistory: $barHistory,
                isPlaying: Self.controller.isPlaying,
                onDebugTapped: onDebugTapped
            )
        }
        .padding(12)
        .background { BackgroundLayer() }
        .clipShape(.rect(cornerRadius: 12))
        .onAppear {
            // Install render tap when visualization is visible
            Self.controller.installRenderTap()
        }
        .onDisappear {
            // Remove render tap when visualization is hidden to save CPU
            Self.controller.removeRenderTap()
        }
        .task(id: Self.controller.isPlaying) {
            // Only process buffers when playing
            guard Self.controller.isPlaying else { return }

            // Get stream reference on MainActor, then process on background thread
            let stream = Self.controller.audioBufferStream
            let viz = visualizer

            // Detach to process FFT/RMS off MainActor
            await Task.detached(priority: .userInitiated) {
                for await buffer in stream {
                    viz.processBuffer(buffer)
                }
            }.value
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
