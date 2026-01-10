//
//  VisualizerDebugView.swift
//  DebugPanel
//
//  Debug interface for toggling processors and normalization modes
//

import SwiftUI
import AppServices
import Playback
import PlayerHeaderView
import Playlist
import Wallpaper

#if DEBUG
public struct VisualizerDebugView: View {
    @Bindable var visualizer: VisualizerDataSource
    @Binding var selectedPlayerType: PlayerControllerType
    @State private var selectedAPIVersion: PlaylistAPIVersion = .loadActive()
    @State private var skipNextAPIVersionPersist = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.playlistService) private var playlistService
    private var hudState = DebugHUDState.shared
    private var themeDebugState = ThemeDebugState.shared
    private var onResetThemePickerState: (() -> Void)?
    private var onResetSiriTip: (() -> Void)?

    public init(
        visualizer: VisualizerDataSource,
        selectedPlayerType: Binding<PlayerControllerType>,
        onResetThemePickerState: (() -> Void)? = nil,
        onResetSiriTip: (() -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self._selectedPlayerType = selectedPlayerType
        self.onResetThemePickerState = onResetThemePickerState
        self.onResetSiriTip = onResetSiriTip
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Performance HUD
                Section {
                    Toggle("Show Performance HUD", isOn: Binding(
                        get: { hudState.isVisible },
                        set: { hudState.isVisible = $0 }
                    ))
                } header: {
                    Text("Performance")
                } footer: {
                    Text("Displays FPS, CPU, GPU memory, RAM, and thermal state.")
                }

                // Wallpaper Debug Overlay
                Section {
                    Toggle("Show Theme Debug Button", isOn: Binding(
                        get: { themeDebugState.showOverlay },
                        set: { themeDebugState.showOverlay = $0 }
                    ))
                } header: {
                    Text("Wallpaper")
                } footer: {
                    Text("Shows a floating button to access wallpaper picker, parameter controls, and thermal throttling settings.")
                }

                // Tip Views & Picker Usage
                Section {
                    Button("Reset Siri Tip") {
                        onResetSiriTip?()
                    }
                    .disabled(onResetSiriTip == nil)
                    Button("Reset Theme Picker State") {
                        onResetThemePickerState?()
                    }
                    .disabled(onResetThemePickerState == nil)
                } header: {
                    Text("Tips & Discoverability")
                } footer: {
                    Text("Resets tip dismissal state and theme picker usage tracking for testing analytics.")
                }

                // Player Controller Selection
                Section {
                    Picker("Player Controller", selection: $selectedPlayerType) {
                        ForEach(PlayerControllerType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: selectedPlayerType) { _, newValue in
                        newValue.persist()
                    }
                } header: {
                    Text("Player Controller")
                } footer: {
                    Text(selectedPlayerType.shortDescription)
                }
                        
                // Playlist API Version
                Section {
                    Picker("API Version", selection: $selectedAPIVersion) {
                        ForEach(PlaylistAPIVersion.allCases) { version in
                            Text(version.displayName).tag(version)
                        }
                    }
                    .onChange(of: selectedAPIVersion) { _, newValue in
                        if skipNextAPIVersionPersist {
                            skipNextAPIVersionPersist = false
                        } else {
                            newValue.persist()
                        }
                        Task {
                            await playlistService?.switchAPIVersion(to: newValue)
                        }
                    }
                    Button("Use Feature Flag") {
                        PlaylistAPIVersion.clearOverride()
                        skipNextAPIVersionPersist = true
                        selectedAPIVersion = .loadActive()
                    }
                } header: {
                    Text("Playlist API")
                } footer: {
                    Text(selectedAPIVersion.shortDescription)
                }

                // Processor & Settings
                Section {
                    Picker("Processor", selection: $visualizer.displayProcessor) {
                        ForEach(ProcessorType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                
                    Toggle("Show FPS Counter", isOn: $visualizer.showFPS)
                    
                    // FFT Settings (shown for FFT or Both)
                    if visualizer.displayProcessor == .fft || visualizer.displayProcessor == .both {
                        HStack {
                            Text("Frequency Weighting")
                            Spacer()
                            Text(String(format: "%.2f", visualizer.fftFrequencyWeighting))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $visualizer.fftFrequencyWeighting, in: 0.0...1.5)
                        HStack {
                            Text("Bass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Treble")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Picker("FFT Normalization", selection: $visualizer.fftNormalizationMode) {
                            ForEach(NormalizationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    }
                    
                    // RMS Settings (shown for RMS or Both)
                    if visualizer.displayProcessor == .rms || visualizer.displayProcessor == .both {
                        Picker("RMS Normalization", selection: $visualizer.rmsNormalizationMode) {
                            ForEach(NormalizationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    }
                } header: {
                    Text("Processor")
                } footer: {
                    switch visualizer.displayProcessor {
                    case .fft:
                        Text("FFT analyzes frequency content. Bass appears in left bars, treble in right bars.")
                    case .rms:
                        Text("RMS measures loudness over time slices. Does not separate frequencies.")
                    case .both:
                        Text("Shows both processors side-by-side for comparison.")
                    }
                }
                
                // Signal Boost
                Section {
                    Toggle("Enabled", isOn: $visualizer.signalBoostEnabled)
                    
                    HStack {
                        Text("Signal Boost")
                        Spacer()
                        Text(String(format: "%.2fx", visualizer.signalBoost))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $visualizer.signalBoost, in: 0.1...10.0)
                        .disabled(!visualizer.signalBoostEnabled)
                    Button("Reset to 1.0x") {
                        visualizer.resetSignalBoost()
                    }
                    .disabled(!visualizer.signalBoostEnabled)
                } header: {
                    Text("Amplification")
                } footer: {
                    Text("Amplify audio signal before processing. 1.0x = no boost.")
                }
                
                // Actions
                Section("Actions") {
                    Button("Reset All Settings") {
                        visualizer.reset()
                    }
                    .foregroundStyle(.red)
                }
            }
            .listRowSeparator(.hidden)
            .navigationTitle("Visualizer Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#endif
