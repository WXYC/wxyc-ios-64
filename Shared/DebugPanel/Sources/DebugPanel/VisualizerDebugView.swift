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
import WXUI

#if DEBUG
public struct VisualizerDebugView: View {
    @Bindable var visualizer: VisualizerDataSource
    @State private var selectedPlayerType: PlayerControllerType = .loadPersisted()
    @State private var skipNextPlayerTypePersist = false
    @State private var selectedHLSEnvironment: HLSEnvironment = .loadActive()
    @State private var cachePurged = false
    @State private var displayMaximumFPS = VisualizerRefreshRate.baselineFramesPerSecond
    @State private var fetchErrorCount: Int?
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

    /// Footer for the Playlist API section: the selected version's own blurb,
    /// plus what the fetch-error row means and the two ways it can mislead.
    ///
    /// The count is per-fetcher and per-launch, so a `0` on a freshly-launched
    /// app is an absence of evidence rather than evidence of health
    /// (WXYC/wxyc-ios-64#267).
    private var playlistAPIFooter: String {
        "api.wxyc.org/flowsheet"
            + " Fetch Errors counts playlist fetches that threw and fell back to an empty playlist — the failures the UI hides by keeping the last good data on screen. Cancellations are excluded. The count is per-fetcher and per-launch."
    }

    /// The fetch-error count, or an em dash before the first sample lands.
    private var fetchErrorCountText: String {
        guard let fetchErrorCount else { return "—" }
        return "\(fetchErrorCount)"
    }

    /// Footer for the Refresh Rate section.
    ///
    /// Names the rate actually detected rather than saying "ProMotion": the
    /// toggle is inert on a 60 Hz display and the reader should be able to see
    /// why without guessing at their hardware.
    private var refreshRateFooter: String {
        guard VisualizerRefreshRate.supportsHighRefreshRate(displayMaximumFramesPerSecond: displayMaximumFPS) else {
            return "This display tops out at \(displayMaximumFPS) Hz, so there is nothing above 60 FPS to switch on. Run on a 120 Hz device, or attach a high-refresh-rate display, to enable it."
        }
        return "Runs the visualizer at this display's full \(displayMaximumFPS) Hz instead of the default 60. Bar smoothing is time-based, so the animation keeps the same shape either way — this buys smoother motion at the cost of extra GPU work and battery. Persists across launches."
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

                    // Playlist API
                    //
                    // The version picker that used to head this section went with
                    // the v1 path (#262): there is one playlist API now, so there
                    // is nothing to pick between. The fetch-error readout stays —
                    // it is about the health of the one remaining path, not about
                    // which path is selected.
                    DebugSection(
                        header: "Playlist API",
                        footer: playlistAPIFooter
                    ) {
                        LabeledContent("Fetch Errors", value: fetchErrorCountText)
                            .task {
                                // Polled rather than observed: the count lives
                                // behind the `PlaylistService` actor on a plain
                                // `Mutex`, not `@Observable` state, so there is
                                // nothing for SwiftUI to subscribe to. One hop a
                                // second is far cheaper than making the counter
                                // observable, and this panel is DEBUG-only.
                                while !Task.isCancelled {
                                    fetchErrorCount = await playlistService.fetchErrorCount()
                                    try? await Task.sleep(for: .seconds(1))
                                }
                            }
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

                    // Visualizer refresh rate
                    DebugSection(
                        header: "Refresh Rate",
                        footer: refreshRateFooter
                    ) {
                        Toggle("Match Display Refresh Rate", isOn: $visualizer.highRefreshRateEnabled)
                            .disabled(!VisualizerRefreshRate.supportsHighRefreshRate(
                                displayMaximumFramesPerSecond: displayMaximumFPS
                            ))
                    }

                    // Signal Boost
                    DebugSection(
                        header: "Amplification",
                        footer: "Amplify audio signal before processing. 1.0x = no boost."
                    ) {
                        Toggle("Enabled", isOn: $visualizer.signalBoostEnabled)

                        LabeledSlider(
                            "Signal Boost",
                            // `signalBoost` is `Float`; `LabeledSlider` is
                            // `Double`-only (its readers are all Double), so
                            // this bridges the same way "Boost" below already
                            // bridges `Double` through a manual `Binding`.
                            value: Binding(
                                get: { Double(visualizer.signalBoost) },
                                set: { visualizer.signalBoost = Float($0) }
                            ),
                            in: 0.1...10.0,
                            format: { String(format: "%.2fx", $0) },
                            resetLabel: "Reset to 1.0x",
                            onReset: { visualizer.resetSignalBoost() },
                            // Not `.disabled(...)` on the control: this section
                            // rests with Amplification off, and a modifier on
                            // the flattened `Group` would grey the "Signal
                            // Boost" label and its live readout too.
                            controlsDisabled: !visualizer.signalBoostEnabled
                        )
                    }

                    // Stream Gain (audio output boost)
                    DebugSection(
                        header: "Stream Gain",
                        footer: streamGainFooter
                    ) {
                        LabeledSlider(
                            "Boost",
                            // `gainDecibels` is `Float`; bridge to `Double`
                            // the same way "Signal Boost" above does.
                            value: Binding(
                                get: { Double(audioController.gainDecibels) },
                                set: { audioController.gainDecibels = Float($0) }
                            ),
                            in: 0...12,
                            step: 0.5,
                            format: { String(format: "%+.1f dB", $0) },
                            monospacedDigitReadout: true,
                            resetLabel: "Reset to 0 dB",
                            onReset: { audioController.gainDecibels = 0 },
                            controlsDisabled: !audioController.supportsGainBoost
                        )
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
            .sheetChrome(title: "Visualizer Settings")
            .onAppear {
                // Resolved here rather than in the property initializer: the
                // window scene the app is showing in is what reports the rate,
                // and it is not connected yet when the view value is created.
                displayMaximumFPS = VisualizerRefreshRate.displayMaximumFramesPerSecond
            }
        }
    }
}
#endif
