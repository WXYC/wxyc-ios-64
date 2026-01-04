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
import WXUI

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

    public init(
        visualizer: VisualizerDataSource,
        selectedPlayerType: Binding<PlayerControllerType>
    ) {
        self.visualizer = visualizer
        self._selectedPlayerType = selectedPlayerType
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
                    Text("Shows a floating button to access wallpaper picker and parameter controls.")
                }

                // Thermal Throttling
                ThermalThrottlingSection()

                // Tip Views
                Section {
                    Button("Reset Tip Views") {
                        SiriTipView.resetState()
                        ThemeTipView.resetState()
                    }
                } header: {
                    Text("Tips")
                } footer: {
                    Text("Resets Siri and Theme tip dismissal state so they appear again on next launch.")
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
                
                // LCD Brightness
                Section {
                    HStack {
                        Text("Min Brightness")
                        Spacer()
                        Text(String(format: "%.2f", visualizer.minBrightness))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $visualizer.minBrightness, in: 0.0...1.5)

                    HStack {
                        Text("Max Brightness")
                        Spacer()
                        Text(String(format: "%.2f", visualizer.maxBrightness))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $visualizer.maxBrightness, in: 0.0...1.5)

                    Button("Reset Brightness") {
                        visualizer.minBrightness = 0.90
                        visualizer.maxBrightness = 1.0
                    }
                } header: {
                    Text("LCD Brightness")
                } footer: {
                    Text("Controls the brightness gradient of LCD segments. Min is applied to top segments, max to bottom.")
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

// MARK: - Thermal Throttling Section

private struct ThermalThrottlingSection: View {
    var body: some View {
        let thermal = AdaptiveThermalController.shared
        Section {
            HStack {
                Text("System Thermal State")
                Spacer()
                Text(thermal.rawThermalState.description)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Target FPS")
                Spacer()
                Text("\(Int(thermal.currentFPS))")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Render Scale")
                Spacer()
                Text("\(Int(thermal.currentScale * 100))%")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Thermal Momentum")
                Spacer()
                Text(String(format: "%.2f", thermal.currentMomentum))
                    .foregroundStyle(.secondary)
            }

            if let shaderID = thermal.activeShaderID {
                HStack {
                    Text("Active Shader")
                    Spacer()
                    Text(shaderID)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Reset Thermal Profiles") {
                ThermalProfileStore.shared.removeAllProfiles()
            }
        } header: {
            Text("Adaptive Thermal Throttling")
        } footer: {
            Text("Continuously optimizes FPS and resolution scale based on thermal state. Reset clears all learned profiles.")
        }
    }
}
#endif
