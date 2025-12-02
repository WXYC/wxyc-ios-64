//
//  PlayerHeaderView.swift
//  PlayerHeaderView
//
//  Main player header view composing playback controls and visualizer
//

import SwiftUI
import StreamingAudioPlayer

// MARK: - Player Header View

/// A complete player header view with playback controls and visualizer
/// Uses AudioPlayerController.shared singleton for playback control
/// Note: The consuming app must call `AudioPlayerController.shared.play(url:)` to start playback
public struct PlayerHeaderView: View {
    /// Uses the shared singleton controller
    private static var controller: AudioPlayerController { AudioPlayerController.shared }
    
    @State private var visualizer = VisualizerDataSource()
    
    /// 2D matrix tracking historical RMS values per bar
    @State var barHistory: [[Float]]
    
    /// Whether to show the FPS debug overlay
    public var showFPS: Bool
    
    public init(previewValues: [Float]? = nil, showFPS: Bool = false) {
        self.showFPS = showFPS
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
                barHistory: $barHistory,
                isPlaying: Self.controller.isPlaying,
                rmsPerBar: visualizer.rmsPerBar,
                showFPS: showFPS,
                normalizationMode: visualizer.normalizationMode
            ) {
                // Cycle through normalization modes on tap
                visualizer.normalizationMode = visualizer.normalizationMode.next
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .onAppear {
            // Connect visualizer to controller's audio buffer
            Self.controller.setAudioBufferHandler { buffer in
                visualizer.processBuffer(buffer)
            }
        }
    }
    
    /// Configures the signal boost for the audio visualizer
    public func signalBoost(_ boost: Float) -> Self {
        visualizer.signalBoost = boost
        return self
    }
}

// MARK: - Helper Functions

/// Creates an initial bar history array with optional preview values
public func createBarHistory(previewValues: [Float]? = nil) -> [[Float]] {
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
    ZStack {
        Rectangle()
            .foregroundStyle(WXYCBackground())
        PlayerHeaderView(showFPS: true)
            .padding()
    }
}
