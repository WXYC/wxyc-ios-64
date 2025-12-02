//
//  VisualizerDebugView.swift
//  PlayerHeaderView
//
//  Debug interface for toggling processors and normalization modes
//

import SwiftUI

#if DEBUG
public struct VisualizerDebugView: View {
    @Bindable var visualizer: VisualizerDataSource
    @Environment(\.dismiss) private var dismiss
    
    public init(visualizer: VisualizerDataSource) {
        self.visualizer = visualizer
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                // Display Control
                Section("Display") {
                    Picker("Show", selection: $visualizer.displayProcessor) {
                        ForEach(ProcessorType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                
                // Processing Control
                Section {
                    Toggle("FFT Processing", isOn: $visualizer.fftProcessingEnabled)
                    Toggle("RMS Processing", isOn: $visualizer.rmsProcessingEnabled)
                } header: {
                    Text("Processing")
                } footer: {
                    Text("Disable processors to save CPU. Disabled processors won't compute data.")
                }
                
                // FFT Normalization
                Section {
                    Picker("Normalization Mode", selection: $visualizer.fftNormalizationMode) {
                        ForEach(NormalizationMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("FFT Normalization")
                } footer: {
                    Text("How FFT frequency magnitudes are normalized for display.")
                }
                
                // RMS Normalization
                Section {
                    Picker("Normalization Mode", selection: $visualizer.rmsNormalizationMode) {
                        ForEach(NormalizationMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("RMS Normalization")
                } footer: {
                    Text("How RMS time-domain values are normalized for display.")
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
            .navigationTitle("Visualizer Settings")
            .navigationBarTitleDisplayMode(.inline)
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

