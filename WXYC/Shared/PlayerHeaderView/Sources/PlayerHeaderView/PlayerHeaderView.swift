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
/// Uses PlaybackControllerManager to handle switching between controller implementations
public struct PlayerHeaderView: View {
    /// Uses the shared controller manager
    private var manager: PlaybackControllerManager { PlaybackControllerManager.shared }
    
    @Bindable var visualizer: VisualizerDataSource
    /// 2D matrix tracking historical RMS values per bar
    @State var barHistory: [[Float]]
    
    /// Selected player controller type for debug switching
    @Binding var selectedPlayerType: PlayerControllerType
    
    /// Callback when player type is changed
    var onPlayerTypeChanged: ((PlayerControllerType) -> Void)?
    /// Callback to present the debug sheet (owned by a parent to avoid TimelineView churn)
    var onPresentDebug: (() -> Void)?
    
    /// Convenience initializer that owns its own visualizer and selection state
    public init(
        previewValues: [Float]? = nil,
        selectedPlayerType: PlayerControllerType = PlayerControllerType.loadPersisted(),
        onPlayerTypeChanged: ((PlayerControllerType) -> Void)? = nil,
        onPresentDebug: (() -> Void)? = nil
    ) {
        self.visualizer = VisualizerDataSource()
        self._selectedPlayerType = State(initialValue: selectedPlayerType).projectedValue
        self.onPlayerTypeChanged = onPlayerTypeChanged
        self.onPresentDebug = onPresentDebug
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

    /// Initializer that reuses a shared visualizer and selection binding (preferred for app usage)
    public init(
        visualizer: VisualizerDataSource,
        selectedPlayerType: Binding<PlayerControllerType>,
        previewValues: [Float]? = nil,
        onPlayerTypeChanged: ((PlayerControllerType) -> Void)? = nil,
        onPresentDebug: (() -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self._selectedPlayerType = selectedPlayerType
        self.onPlayerTypeChanged = onPlayerTypeChanged
        self.onPresentDebug = onPresentDebug
        if let values = previewValues {
            self._barHistory = State(initialValue: values.map { value in
                var history = Array(repeating: Float(0), count: VisualizerConstants.historyLength)
                history[0] = value
                return history
            })
        } else {
            self._barHistory = State(initialValue: Array(
                repeating: Array(repeating: 0, count: VisualizerConstants.historyLength),
                count: VisualizerConstants.barAmount
            ))
        }
    }
    
    public var body: some View {
        HStack(alignment: .center) {
            PlaybackControlsView(isPlaying: manager.isPlaying, isLoading: manager.isLoading) {
                manager.toggle()
            }

            VisualizerTimelineView(
                visualizer: visualizer,
                barHistory: $barHistory,
                isPlaying: manager.isPlaying,
                rmsPerBar: visualizer.rmsPerBar,
                onModeTapped: {
                    // Cycle through normalization modes on tap (non-DEBUG builds only)
                    // visualizer.rmsNormalizationMode = visualizer.rmsNormalizationMode.next
                },
                onDebugTapped: {
                    #if DEBUG
                    onPresentDebug?()
                    #endif
                }
            )
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .onAppear {
            // Connect visualizer to controller's audio buffer
            manager.setAudioBufferHandler { buffer in
                visualizer.processBuffer(buffer)
            }
        }
        .onChange(of: selectedPlayerType) { _, newType in
            // Switch to the new controller type
            manager.switchTo(newType)
            // Persist the selection
            newType.persist()
            // Call the callback if provided
            onPlayerTypeChanged?(newType)
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
    ZStack {
        Rectangle()
            .foregroundStyle(WXYCBackground())
        PlayerHeaderView()
            .padding()
    }
}
