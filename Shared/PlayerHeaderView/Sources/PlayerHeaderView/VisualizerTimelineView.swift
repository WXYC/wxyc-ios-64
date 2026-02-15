//
//  VisualizerTimelineView.swift
//  PlayerHeaderView
//
//  TimelineView-based animated audio visualizer with falling dots on stop
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

// MARK: - Visualizer Timeline View

/// A SwiftUI view that displays an animated audio visualizer using historical bar data
public struct VisualizerTimelineView: View {
    @Bindable var visualizer: VisualizerDataSource
    @Binding var barHistory: [[Float]]
    var onDebugTapped: (() -> Void)?
    
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
    
    /// Cached showFPS value to avoid Observable access triggering rebuilds
    @State private var cachedShowFPS = false
    
    /// Pre-allocated BarData array to avoid allocations each frame
    @State private var barDataCache: [BarData] = (0..<VisualizerConstants.barAmount).map {
        BarData(category: String($0), value: 0)
    }
    
    /// Animation runs while the visualizer is active (consuming or draining) OR while dots are falling
    private var isAnimating: Bool {
        visualizer.isActive || isFalling
    }

    public init(
        visualizer: VisualizerDataSource,
        barHistory: Binding<[[Float]]>,
        onDebugTapped: (() -> Void)? = nil
    ) {
        self.visualizer = visualizer
        self._barHistory = barHistory
        self.onDebugTapped = onDebugTapped
    }
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: VisualizerConstants.updateInterval, paused: !isAnimating)) { timeline in
            LCDSpectrumAnalyzerView(
                data: barDataCache,
                maxValue: Double(VisualizerConstants.magnitudeLimit)
            )
            .frame(height: 75)
            .padding()
            .background(
                HeaderItemBackgroundStyle()
            )
            .cornerRadius(10)
            .overlay(alignment: .topTrailing) {
                if cachedShowFPS {
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
        .onChange(of: visualizer.isActive) { wasActive, nowActive in
            if wasActive && !nowActive {
                // Delay buffer fully drained - start falling animation
                startFalling()
            }
        }
        .onChange(of: visualizer.showFPS) { _, newValue in
            cachedShowFPS = newValue
        }
        .onAppear {
            cachedShowFPS = visualizer.showFPS
        }
#if DEBUG
        .onTapGesture {
            onDebugTapped?()
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
        if visualizer.isActive {
            updatePlaybackData()
        } else if isFalling {
            updateFallingDots()
        }
    }
    
    /// Update visualizer with live audio data using frame-level smoothing
    /// This interpolates between audio buffer updates to achieve smooth 60 FPS animation
    private func updatePlaybackData() {
        // Pull the next eligible frame from the delay buffer into fftMagnitudes/rmsPerBar
        visualizer.dequeueNextFrame()

        // Cache displayData to avoid repeated computed property access
        let currentDisplayData = displayData
        
        for barIndex in 0..<VisualizerConstants.barAmount {
            // Get target value from audio data
            let targetValue = barIndex < currentDisplayData.count 
                ? min(currentDisplayData[barIndex], VisualizerConstants.magnitudeLimit) 
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
            
            // Update barHistory for external consumers (e.g., startFalling)
            barHistory[barIndex][0] = smoothedValue
            
            // Update pre-allocated BarData cache (avoids allocation each frame)
            barDataCache[barIndex] = BarData(
                category: String(barIndex),
                value: Int(smoothedValue)
            )
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
    
                // Update BarData with falling dot position
                let dotSegment = Int((fallingDots[barIndex] / VisualizerConstants.magnitudeLimit) * 8) - 1
                barDataCache[barIndex] = BarData(
                    category: String(barIndex),
                    value: 0,
                    singleDotPosition: dotSegment >= 0 ? dotSegment : nil
                )
            } else {
                // Snap to zero when very small
                fallingDots[barIndex] = 0
                barDataCache[barIndex] = BarData(
                    category: String(barIndex),
                    value: 0,
                    singleDotPosition: nil
                )
            }
        }
        
        // Stop animation when all dots have fallen
        if allZero {
            isFalling = false
        }
    }
}
