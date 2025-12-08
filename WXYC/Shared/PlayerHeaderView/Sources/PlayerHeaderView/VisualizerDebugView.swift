//
//  VisualizerDebugView.swift
//  PlayerHeaderView
//
//  Debug interface for toggling processors and normalization modes
//

import SwiftUI
import Playback

#if DEBUG
struct VisualizerDebugView: View {
    @Bindable var visualizer: VisualizerDataSource
    @Binding var selectedPlayerType: PlayerControllerType
    var onPlayerTypeChanged: ((PlayerControllerType) -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    init(
        visualizer: VisualizerDataSource,
        selectedPlayerType: Binding<PlayerControllerType>,
        onPlayerTypeChanged: ((PlayerControllerType) -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self._selectedPlayerType = selectedPlayerType
        self.onPlayerTypeChanged = onPlayerTypeChanged
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Player Controller Selection
                Section {
                    Picker("Player Controller", selection: $selectedPlayerType) {
                        ForEach(PlayerControllerType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: selectedPlayerType) { _, newValue in
                        newValue.persist()
                        onPlayerTypeChanged?(newValue)
                    }
                } header: {
                    Text("Player Controller")
                } footer: {
                    Text(selectedPlayerType.shortDescription)
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
#endif

