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
    
    /// Smoothed display values that animate at frame rate (interpolates between audio updates)
    @State private var smoothedValues: [Float] = Array(repeating: 0, count: VisualizerConstants.barAmount)
    
    /// The current display's maximum refresh rate, resolved once the view is on screen.
    ///
    /// Starts at the 60 FPS baseline so the first frames are scheduled conservatively
    /// on a display that turns out not to support anything faster.
    @State private var displayMaximumFPS = VisualizerRefreshRate.baselineFramesPerSecond
    
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

    /// How often the timeline is allowed to tick.
    ///
    /// Read from the data source rather than cached, unlike `showFPS`: a change
    /// here has to rebuild the `TimelineView` for the new schedule to take effect.
    private var minimumInterval: Double {
        VisualizerRefreshRate.minimumInterval(
            highRefreshRateEnabled: visualizer.highRefreshRateEnabled,
            displayMaximumFramesPerSecond: displayMaximumFPS
        )
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
        TimelineView(.animation(minimumInterval: minimumInterval, paused: !isAnimating)) { timeline in
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
            .onChange(of: timeline.date) { previousDate, currentDate in
                fpsCounter.recordFrame()
                updateFrame(elapsed: currentDate.timeIntervalSince(previousDate))
            }
        }
        .onChange(of: visualizer.isActive) { wasActive, nowActive in
            if !wasActive && nowActive {
                // Resuming — clear stale smoothed values so bars start from zero
                smoothedValues = Array(repeating: 0, count: VisualizerConstants.barAmount)
                for barIndex in 0..<VisualizerConstants.barAmount {
                    barDataCache[barIndex] = BarData(category: String(barIndex), value: 0)
                }
                isFalling = false
            } else if wasActive && !nowActive {
                // Delay buffer fully drained — start falling animation
                startFalling()
            }
        }
        .onChange(of: visualizer.showFPS) { _, newValue in
            cachedShowFPS = newValue
        }
        .onChange(of: visualizer.highRefreshRateEnabled) {
            // Re-resolve rather than trust the value cached at `onAppear`: on a Mac
            // or an iPad with an external display, the window may have moved to a
            // different panel since this view appeared.
            displayMaximumFPS = VisualizerRefreshRate.displayMaximumFramesPerSecond
        }
        .onAppear {
            cachedShowFPS = visualizer.showFPS
            displayMaximumFPS = VisualizerRefreshRate.displayMaximumFramesPerSecond
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
    
    private func updateFrame(elapsed: TimeInterval) {
        if visualizer.isActive {
            updatePlaybackData(elapsed: elapsed)
        } else if isFalling {
            updateFallingDots(elapsed: elapsed)
        }
    }
    
    /// Update visualizer with live audio data using frame-level smoothing
    ///
    /// This interpolates between audio buffer updates to achieve smooth animation.
    /// Smoothing is scaled by `elapsed` so the bars behave identically whether the
    /// timeline is ticking at 60 FPS or at a ProMotion display's full rate.
    private func updatePlaybackData(elapsed: TimeInterval) {
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
            let smoothedValue = VisualizerSmoothing.smooth(
                current: smoothedValues[barIndex],
                target: targetValue,
                elapsed: elapsed
            )
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
    ///
    /// The fall takes the same wall-clock time at any refresh rate; `elapsed`
    /// is what decouples it from how often this runs.
    private func updateFallingDots(elapsed: TimeInterval) {
        var allZero = true
        
        for barIndex in 0..<VisualizerConstants.barAmount {
            if fallingDots[barIndex] > 0.5 {
                // Decay exponentially
                fallingDots[barIndex] = VisualizerSmoothing.decayedDot(fallingDots[barIndex], elapsed: elapsed)
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
