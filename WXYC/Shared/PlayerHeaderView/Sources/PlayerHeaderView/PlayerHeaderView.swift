//
//  PlayerHeaderView.swift
//  PlayerHeaderView
//
//  Main player header view composing playback controls and visualizer
//

import SwiftUI
import Playback

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
    
    /// Callback when player type is changed
    var onPlayerTypeChanged: ((PlayerControllerType) -> Void)?
    
    /// Callback when debug tap occurs (DEBUG only)
    var onDebugTapped: (() -> Void)?
    
    public init(
        visualizer: VisualizerDataSource,
        selectedPlayerType: Binding<PlayerControllerType>,
        previewValues: [Float]? = nil,
        onPlayerTypeChanged: ((PlayerControllerType) -> Void)? = nil,
        onDebugTapped: (() -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self._selectedPlayerType = selectedPlayerType
        self.onPlayerTypeChanged = onPlayerTypeChanged
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
        .onAppear {
            // Connect visualizer to controller's audio buffer
            Self.controller.setAudioBufferHandler { buffer in
                visualizer.processBuffer(buffer)
            }
        }
        .onChange(of: selectedPlayerType) { _, newType in
            // Switch the player when type changes
            Task { @MainActor in
                let newPlayer = AudioPlayerController.createPlayer(for: newType)
                Self.controller.replacePlayer(newPlayer)
                // Reconnect visualizer to new player's audio buffer
                Self.controller.setAudioBufferHandler { buffer in
                    visualizer.processBuffer(buffer)
                }
                // Call the callback if provided
                onPlayerTypeChanged?(newType)
            }
        }
    }
    
    /// Configures the signal boost for the audio visualizer
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
            .foregroundStyle(WXYCBackground())
        PlayerHeaderView(
            visualizer: VisualizerDataSource(),
            selectedPlayerType: $selectedPlayerType
        )
        .padding()
    }
}
