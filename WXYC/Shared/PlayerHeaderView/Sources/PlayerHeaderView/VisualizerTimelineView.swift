//
//  VisualizerTimelineView.swift
//  PlayerHeaderView
//
//  TimelineView-based animated audio visualizer with falling dots on stop
//

import SwiftUI
import StreamingAudioPlayer

// MARK: - Visualizer Timeline View

/// A SwiftUI view that displays an animated audio visualizer using historical bar data
public struct VisualizerTimelineView: View {
    @Binding public var barHistory: [[Float]]
    public var isPlaying: Bool
    public var rmsPerBar: [Float]
    public var normalizationMode: NormalizationMode
    public var onModeTapped: (() -> Void)?
    
    /// Falling dot positions (one per bar) - used when playback stops
    @State private var fallingDots: [Float] = Array(repeating: 0, count: VisualizerConstants.barAmount)
    
    /// Whether the falling animation is active
    @State private var isFalling: Bool = false
    
    /// Decay factor per frame for falling dots (0.0–1.0). Lower = faster fall.
    /// At 60 FPS, 0.92 gives a nice ~1 second fall to zero.
    private let fallDecayFactor: Float = 0.92
    
    @State private var fpsCounter = FPSCounter()
    @State private var showModeIndicator = false
    
#if DEBUG
    let showFPS = true
#else
    let showFPS = false
#endif
    
    /// Animation runs during playback OR while dots are falling
    private var isAnimating: Bool {
        isPlaying || isFalling
    }
    
    public init(barHistory: Binding<[[Float]]>, isPlaying: Bool, rmsPerBar: [Float], showFPS: Bool = false, normalizationMode: NormalizationMode = .ema, onModeTapped: (() -> Void)? = nil) {
        self._barHistory = barHistory
        self.isPlaying = isPlaying
        self.rmsPerBar = rmsPerBar
        self.normalizationMode = normalizationMode
        #if DEBUG
        self.onModeTapped = nil
        #else
        self.onModeTapped = onModeTapped
        #endif
    }
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: VisualizerConstants.updateInterval, paused: !isAnimating)) { timeline in
            LCDBarChartView(
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
                maxValue: Double(VisualizerConstants.magnitudeLimit)
            )
            .frame(height: 75)
            .padding()
            .background(
                HeaderItemBackgroundStyle()
            )
            .cornerRadius(10)
            .overlay(alignment: .topTrailing) {
                if showFPS {
                    FPSDebugView(fps: fpsCounter.fps)
                        .padding(8)
                }
            }
            .overlay(alignment: .center) {
                if showModeIndicator {
                    ModeIndicatorView(mode: normalizationMode)
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
        .onTapGesture {
#if DEBUG
            onModeTapped?()
            showModeIndicatorBriefly()
#endif
        }
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
    
    /// Update visualizer with live audio data
    private func updatePlaybackData() {
        for barIndex in 0..<VisualizerConstants.barAmount {
            // Shift history buffer
            for historyIndex in stride(from: VisualizerConstants.historyLength - 1, through: 1, by: -1) {
                barHistory[barIndex][historyIndex] = barHistory[barIndex][historyIndex - 1]
            }
            
            let newValue = barIndex < rmsPerBar.count 
                ? min(rmsPerBar[barIndex], VisualizerConstants.magnitudeLimit) 
                : 0
            barHistory[barIndex][0] = newValue
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
