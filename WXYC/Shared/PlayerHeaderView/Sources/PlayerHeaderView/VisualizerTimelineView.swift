//
//  VisualizerTimelineView.swift
//  PlayerHeaderView
//
//  TimelineView-based animated audio visualizer with falling dots on stop
//

import SwiftUI
import Playback

// MARK: - Visualizer Timeline View

/// A SwiftUI view that displays an animated audio visualizer using historical bar data
public struct VisualizerTimelineView: View {
    @Bindable var visualizer: VisualizerDataSource
    @Binding var barHistory: [[Float]]
    @Binding var selectedPlayerType: PlayerControllerType
    var isPlaying: Bool
    var rmsPerBar: [Float]
    var onModeTapped: (() -> Void)?
    var onPlayerTypeChanged: ((PlayerControllerType) -> Void)?
    
    /// Computed property to get the current display data based on displayProcessor
    private var displayData: [Float] {
        switch visualizer.displayProcessor {
        case .fft:
            return visualizer.fftMagnitudes
        case .rms:
            return visualizer.rmsPerBar
        case .both:
            // For "both", default to RMS for now (could be enhanced to show side-by-side)
            return visualizer.rmsPerBar
        }
    }
    
    /// Computed property to get the current normalization mode for display
    private var displayNormalizationMode: NormalizationMode {
        switch visualizer.displayProcessor {
        case .fft:
            return visualizer.fftNormalizationMode
        case .rms, .both:
            return visualizer.rmsNormalizationMode
        }
    }
    
    #if DEBUG
    @State private var showDebugSheet = false
    #endif
    
    /// Falling dot positions (one per bar) - used when playback stops
    @State private var fallingDots: [Float] = Array(repeating: 0, count: VisualizerConstants.barAmount)
    
    /// Whether the falling animation is active
    @State private var isFalling: Bool = false
    
    /// Decay factor per frame for falling dots (0.0–1.0). Lower = faster fall.
    /// At 60 FPS, 0.92 gives a nice ~1 second fall to zero.
    private let fallDecayFactor: Float = 0.92
    
    /// Smoothed display values that animate at frame rate (interpolates between audio updates)
    @State private var smoothedValues: [Float] = Array(repeating: 0, count: VisualizerConstants.barAmount)
    
    /// Attack factor for rising values (higher = faster response to increases)
    /// At 60 FPS, 0.5 gives quick attack (~2 frames to reach target)
    private let attackFactor: Float = 0.5
    
    /// Decay factor for falling values (lower = slower decay for smooth falloff)
    /// At 60 FPS, 0.85 gives a smooth ~0.5 second decay
    private let decayFactor: Float = 0.85
    
    @State private var fpsCounter = FPSCounter()
    @State private var showModeIndicator = false
    
    /// Animation runs during playback OR while dots are falling
    private var isAnimating: Bool {
        isPlaying || isFalling
    }
    
    public init(
        visualizer: VisualizerDataSource,
        barHistory: Binding<[[Float]]>,
        selectedPlayerType: Binding<PlayerControllerType>,
        isPlaying: Bool,
        rmsPerBar: [Float],
        onModeTapped: (() -> Void)? = nil,
        onPlayerTypeChanged: ((PlayerControllerType) -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self._barHistory = barHistory
        self._selectedPlayerType = selectedPlayerType
        self.isPlaying = isPlaying
        self.rmsPerBar = rmsPerBar
        self.onPlayerTypeChanged = onPlayerTypeChanged
        #if DEBUG
        self.onModeTapped = nil
        #else
        self.onModeTapped = onModeTapped
        #endif
    }
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: VisualizerConstants.updateInterval, paused: !isAnimating)) { timeline in
            LCDSpectrumAnalyzerView(
                data: barHistory.enumerated().map {
                    index,
                    history in
                    if isPlaying {
                        // Normal playback - show full bars
                        return BarData(
                            category: String(index),
                            value: Int(history[0])
                        )
                    } else {
                        // Stopped - show single falling dot (or nothing if at 0)
                        let dotSegment = Int((fallingDots[index] / VisualizerConstants.magnitudeLimit) * 8) - 1
                        return BarData(
                            category: String(index),
                            value: 0,
                            singleDotPosition: dotSegment >= 0 ? dotSegment : nil
                        )
                    }
                },
                maxValue: Double(VisualizerConstants.magnitudeLimit),
                minBrightness: visualizer.minBrightness,
                maxBrightness: visualizer.maxBrightness
            )
            .frame(height: 75)
            .padding()
            .background(
                HeaderItemBackgroundStyle()
            )
            .cornerRadius(10)
            .overlay(alignment: .topTrailing) {
                if visualizer.showFPS {
                    FPSDebugView(fps: fpsCounter.fps)
                        .padding(8)
                }
            }
            .overlay(alignment: .center) {
                if showModeIndicator {
                    ModeIndicatorView(mode: displayNormalizationMode)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .onChange(of: timeline.date) {
                fpsCounter.recordFrame()
                updateFrame()
            }
        }
        .onChange(of: isPlaying) { wasPlaying, nowPlaying in
            if wasPlaying && !nowPlaying {
                // Playback stopped - start falling animation
                startFalling()
            }
        }
#if DEBUG
        .onTapGesture {
            showDebugSheet = true
            onModeTapped?()
            showModeIndicatorBriefly()
        }
        .sheet(isPresented: $showDebugSheet) {
            VisualizerDebugView(
                visualizer: visualizer,
                selectedPlayerType: $selectedPlayerType,
                onPlayerTypeChanged: onPlayerTypeChanged
            )
            .presentationDetents([.fraction(0.75)])
        }
#endif
    }
    
    /// Capture current bar tops and start the falling animation
    private func startFalling() {
        // Capture the top position of each bar as a falling dot
        for barIndex in 0..<VisualizerConstants.barAmount {
            fallingDots[barIndex] = barHistory[barIndex][0]
        }
        isFalling = true
    }
    
    private func updateFrame() {
        if isPlaying {
            updatePlaybackData()
        } else if isFalling {
            updateFallingDots()
        }
    }
    
    /// Update visualizer with live audio data using frame-level smoothing
    /// This interpolates between audio buffer updates to achieve smooth 60 FPS animation
    private func updatePlaybackData() {
        for barIndex in 0..<VisualizerConstants.barAmount {
            // Shift history buffer
            for historyIndex in stride(from: VisualizerConstants.historyLength - 1, through: 1, by: -1) {
                barHistory[barIndex][historyIndex] = barHistory[barIndex][historyIndex - 1]
            }
            
            // Get target value from audio data
            let targetValue = barIndex < displayData.count 
                ? min(displayData[barIndex], VisualizerConstants.magnitudeLimit) 
                : Float(0)
            
            // Apply asymmetric smoothing: fast attack, slow decay
            let currentSmoothed = smoothedValues[barIndex]
            let smoothedValue: Float
            if targetValue > currentSmoothed {
                // Rising: fast attack to catch beats/peaks
                smoothedValue = currentSmoothed + (targetValue - currentSmoothed) * attackFactor
            } else {
                // Falling: smooth decay for visual appeal
                smoothedValue = currentSmoothed * decayFactor + targetValue * (1 - decayFactor)
            }
            smoothedValues[barIndex] = smoothedValue
            
            barHistory[barIndex][0] = smoothedValue
        }
    }
    
    /// Animate falling dots decaying to zero
    private func updateFallingDots() {
        var allZero = true
        
        for barIndex in 0..<VisualizerConstants.barAmount {
            if fallingDots[barIndex] > 0.5 {
                // Decay exponentially
                fallingDots[barIndex] *= fallDecayFactor
                allZero = false
            } else {
                // Snap to zero when very small
                fallingDots[barIndex] = 0
            }
        }
        
        // Stop animation when all dots have fallen
        if allZero {
            isFalling = false
        }
    }
    
    private func showModeIndicatorBriefly() {
        withAnimation(.easeIn(duration: 0.15)) {
            showModeIndicator = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                showModeIndicator = false
            }
        }
    }
}
