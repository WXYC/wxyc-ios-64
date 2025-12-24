//
//  PlayerHeaderView.swift
//  PlayerHeaderView
//
//  Main player header view composing playback controls and visualizer
//

import SwiftUI
import Playback
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
    
    /// Selected player controller type for debug switching
    @Binding var selectedPlayerType: PlayerControllerType
    
    /// Callback when debug tap occurs (DEBUG only)
    var onDebugTapped: (() -> Void)?
    
    public init(
        visualizer: VisualizerDataSource,
        selectedPlayerType: Binding<PlayerControllerType>,
        previewValues: [Float]? = nil,
        onDebugTapped: (() -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self._selectedPlayerType = selectedPlayerType
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
            PlaybackControlsView(isPlaying: Self.controller.isPlaying, isLoading: Self.controller.isLoading) {
                Self.controller.toggle()
            }

            VisualizerTimelineView(
                visualizer: visualizer,
                barHistory: $barHistory,
                isPlaying: Self.controller.isPlaying,
                rmsPerBar: visualizer.rmsPerBar,
                onModeTapped: nil,
                onDebugTapped: onDebugTapped
            )
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .task {
            // Connect visualizer to controller's audio buffer stream
            for await buffer in Self.controller.audioBufferStream {
                visualizer.processBuffer(buffer)
            }
        }
        .onChange(of: selectedPlayerType) { _, newType in
            // Switch the player when type changes
            Task { @MainActor in
                Self.controller.playerType = newType
                // Note: HeaderView relies on AudioPlayerController's internal bridging,
                // so the existing stream loop in .task should continue to work or
                // may need to be restarted if the iterator terminates?
                // AudioPlayerController.audioBufferStream returns a bridged stream,
                // so the stream itself shouldn't terminate unless AudioPlayerController explicitly ends it.
                // Assuming AudioPlayerController keeps the same stream alive across replacements.
                
                // If stream does terminate, we might need a way to restart the loop.
                // But .task restarts if identity changes... local identity hasn't changed.
                // If AudioPlayerController's stream implementation is robust, it shouldn't end on replace.
            }
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

// MARK: - Preview

#Preview {
    @Previewable @State var selectedPlayerType = PlayerControllerType.loadPersisted()
    
    ZStack {
        Rectangle()
            .foregroundStyle(WXYCGradient())
        PlayerHeaderView(
            visualizer: VisualizerDataSource(),
            selectedPlayerType: $selectedPlayerType
        )
        .padding()
    }
}
