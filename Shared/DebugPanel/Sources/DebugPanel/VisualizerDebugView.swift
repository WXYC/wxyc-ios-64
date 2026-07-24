//
//  VisualizerDebugView.swift
//  DebugPanel
//
//  Debug interface for toggling processors and normalization modes
//
//  Created by Jake Bromberg on 12/02/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import AppServices
import Caching
import Playback
import PlayerHeaderView
import Playlist
import Wallpaper

#if DEBUG
public struct VisualizerDebugView: View {
    @Bindable var visualizer: VisualizerDataSource
    @State private var selectedAPIVersion: PlaylistAPIVersion = .loadActive()
    @State private var skipNextAPIVersionPersist = false
    @State private var selectedPlayerType: PlayerControllerType = .loadPersisted()
    @State private var skipNextPlayerTypePersist = false
    @State private var selectedHLSEnvironment: HLSEnvironment = .loadActive()
    @State private var cachePurged = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.playlistService) private var playlistService
    private var hudState = DebugHUDState.shared
    private var themeDebugState = ThemeDebugState.shared
    private var audioController = AudioPlayerController.shared
    private var onResetThemePickerState: (() -> Void)?
    private var onResetSiriTip: (() -> Void)?
    private var onResetTicketCTA: (() -> Void)?

    public init(
        visualizer: VisualizerDataSource,
        onResetThemePickerState: (() -> Void)? = nil,
        onResetSiriTip: (() -> Void)? = nil,
        onResetTicketCTA: (() -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self.onResetThemePickerState = onResetThemePickerState
        self.onResetSiriTip = onResetSiriTip
        self.onResetTicketCTA = onResetTicketCTA
    }

    private var streamGainFooter: String {
        if audioController.supportsGainBoost {
            "Boosts the live stream's output level. The stream tops out around −6 dBFS, so ~+6 dB fills the headroom to 0 dBFS; higher values clip. Affects audio output only (not the visualizer). Persists across launches — use Reset to clear."
        } else {
            "Unavailable for the current player. Switch to the MP3 streamer in the Player section and relaunch to enable a stream boost."
        }
    }

    private var processorFooter: String {
        switch visualizer.displayProcessor {
        case .fft:
            "FFT analyzes frequency content. Bass appears in left bars, treble in right bars."
        case .rms:
            "RMS measures loudness over time slices. Does not separate frequencies."
        case .both:
            "Shows both processors side-by-side for comparison."
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Performance HUD
                    DebugSection(
                        header: "Performance",
                        footer: "Displays FPS, CPU, GPU memory, RAM, and thermal state."
                    ) {
                        Toggle("Show Performance HUD", isOn: Binding(
                            get: { hudState.isVisible },
                            set: { hudState.isVisible = $0 }
                        ))
                    }

                    // Wallpaper Debug Overlay
                    DebugSection(
                        header: "Wallpaper",
                        footer: "Shows a floating button to access wallpaper picker, parameter controls, and quality throttling settings."
                    ) {
                        Toggle("Show Theme Debug Button", isOn: Binding(
                            get: { themeDebugState.showOverlay },
                            set: { themeDebugState.showOverlay = $0 }
                        ))
                    }

                    // On Tour (Box Office ticket)
                    DebugSection(
                        header: "On Tour",
                        footer: "Shows a mock Box Office concert ticket on the now-playing (first) item. Tap that item to see it in the detail view."
                    ) {
                        Toggle("Mock ticket on first item", isOn: Binding(
                            get: { OnTourShowsDebugState.shared.mockFirstItemEnabled },
                            set: { OnTourShowsDebugState.shared.mockFirstItemEnabled = $0 }
                        ))
                    }

                    // Tip Views & Picker Usage
                    DebugSection(
                        header: "Tips & Discoverability",
                        footer: "Resets tip dismissal state and theme picker usage tracking for testing analytics."
                    ) {
                        Button("Reset Siri Tip") {
                            onResetSiriTip?()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(onResetSiriTip == nil)
                        Button("Reset Theme Picker State") {
                            onResetThemePickerState?()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(onResetThemePickerState == nil)
                        Button("Reset Ticket Feature CTA") {
                            onResetTicketCTA?()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(onResetTicketCTA == nil)
                    }

                    // Cache
                    DebugSection(
                        header: "Cache",
                        footer: cachePurged ? "All caches purged." : "Removes all cached album art, playlist data, and metadata."
                    ) {
                        Button("Purge All Caches", role: .destructive) {
                            Task {
                                await CacheCoordinator.AlbumArt.clearAll()
                                await CacheCoordinator.Playlist.clearAll()
                                await CacheCoordinator.Metadata.clearAll()
                                cachePurged = true
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(cachePurged)
                    }

                    // Playlist API Version
                    DebugSection(
                        header: "Playlist API",
                        footer: selectedAPIVersion.shortDescription
                    ) {
                        LabeledContent("API Version") {
                            Picker("API Version", selection: $selectedAPIVersion) {
                                ForEach(PlaylistAPIVersion.allCases) { version in
                                    Text(version.displayName).tag(version)
                                }
                            }
                            .labelsHidden()
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Player Controller
                    DebugSection(
                        header: "Player",
                        footer: selectedPlayerType.shortDescription + " Restart the app to apply."
                    ) {
                        LabeledContent("Player") {
                            Picker("Player", selection: $selectedPlayerType) {
                                ForEach(PlayerControllerType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .labelsHidden()
                        }
                        .onChange(of: selectedPlayerType) { _, newValue in
                            if skipNextPlayerTypePersist {
                                skipNextPlayerTypePersist = false
                            } else {
                                newValue.persist()
                            }
                        }
                        if selectedPlayerType == .hlsPlayer {
                            LabeledContent("HLS Environment") {
                                Picker("HLS Environment", selection: $selectedHLSEnvironment) {
                                    ForEach(HLSEnvironment.allCases) { env in
                                        Text(env.displayName).tag(env)
                                    }
                                }
                                .labelsHidden()
                            }
                            .onChange(of: selectedHLSEnvironment) { _, newValue in
                                newValue.persist()
                            }
                        }
                        Button("Use Feature Flag") {
                            PlayerControllerType.clearPersisted()
                            skipNextPlayerTypePersist = true
                            selectedPlayerType = .loadPersisted()
                            HLSEnvironment.clearOverride()
                            selectedHLSEnvironment = .loadActive()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Processor & Settings
                    DebugSection(
                        header: "Processor",
                        footer: processorFooter
                    ) {
                        LabeledContent("Processor") {
                            Picker("Processor", selection: $visualizer.displayProcessor) {
                                ForEach(ProcessorType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .labelsHidden()
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

                            LabeledContent("FFT Normalization") {
                                Picker("FFT Normalization", selection: $visualizer.fftNormalizationMode) {
                                    ForEach(NormalizationMode.allCases, id: \.self) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        // RMS Settings (shown for RMS or Both)
                        if visualizer.displayProcessor == .rms || visualizer.displayProcessor == .both {
                            LabeledContent("RMS Normalization") {
                                Picker("RMS Normalization", selection: $visualizer.rmsNormalizationMode) {
                                    ForEach(NormalizationMode.allCases, id: \.self) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }

                    // Signal Boost
                    DebugSection(
                        header: "Amplification",
                        footer: "Amplify audio signal before processing. 1.0x = no boost."
                    ) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!visualizer.signalBoostEnabled)
                    }

                    // Stream Gain (audio output boost)
                    DebugSection(
                        header: "Stream Gain",
                        footer: streamGainFooter
                    ) {
                        HStack {
                            Text("Boost")
                            Spacer()
                            Text(String(format: "%+.1f dB", audioController.gainDecibels))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { audioController.gainDecibels },
                                set: { audioController.gainDecibels = $0 }
                            ),
                            in: 0...12,
                            step: 0.5
                        )
                        .disabled(!audioController.supportsGainBoost)
                        Button("Reset to 0 dB") {
                            audioController.gainDecibels = 0
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!audioController.supportsGainBoost)
                    }

                    // Actions
                    DebugSection(header: "Actions") {
                        Button("Reset All Settings") {
                            visualizer.reset()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.red)
                    }
                }
                .padding()
            }
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
