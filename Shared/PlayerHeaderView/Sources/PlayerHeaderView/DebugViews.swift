//
//  DebugViews.swift
//  PlayerHeaderView
//
//  Debug and development overlay views for audio visualization
//

import SwiftUI

// MARK: - FPS Counter

/// Tracks frame timing for FPS calculation
@Observable
public final class FPSCounter {
    var fps: Double = 0

    private var lastFrameTime: CFAbsoluteTime = 0
    private var frameTimes: [CFAbsoluteTime] = []
    private let sampleCount = 30

    public init() {}

    public func recordFrame() {
        let now = CFAbsoluteTimeGetCurrent()

        if lastFrameTime > 0 {
            let delta = now - lastFrameTime
            frameTimes.append(delta)

            // Keep rolling window of samples
            if frameTimes.count > sampleCount {
                frameTimes.removeFirst()
            }

            // Calculate average FPS
            if frameTimes.count > 1 {
                let averageDelta = frameTimes.reduce(0, +) / Double(frameTimes.count)
                fps = 1.0 / averageDelta
            }
        }

        lastFrameTime = now
    }
}

// MARK: - FPS Debug View

/// A small overlay view that displays the current FPS
public struct FPSDebugView: View {
    let fps: Double

    public init(fps: Double) {
        self.fps = fps
    }

    public var body: some View {
        Text(String(format: "%.1f FPS", fps))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Mode Indicator View

/// A brief indicator showing the current normalization mode
struct ModeIndicatorView: View {
    let mode: NormalizationMode

    private var icon: String {
        switch mode {
        case .none: "waveform.slash"
        case .ema: "waveform.path"
        case .circularBuffer: "clock.arrow.circlepath"
        case .perBandEMA: "slider.horizontal.3"
        }
    }

    private var label: String {
        switch mode {
        case .none: "Off"
        case .ema: "EMA"
        case .circularBuffer: "Buffer"
        case .perBandEMA: "Per-Band"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.7))
        .clipShape(Capsule())
    }
}
