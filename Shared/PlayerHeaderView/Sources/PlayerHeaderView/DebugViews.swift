//
//  DebugViews.swift
//  PlayerHeaderView
//
//  Debug and development overlay views for audio visualization
//

import SwiftUI

// MARK: - Blend Mode Debug State

/// All available SwiftUI blend modes for debug picker
public enum DebugBlendMode: String, CaseIterable, Identifiable, Sendable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity
    case sourceAtop
    case destinationOver
    case destinationOut
    case plusDarker
    case plusLighter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .darken: "Darken"
        case .lighten: "Lighten"
        case .colorDodge: "Color Dodge"
        case .colorBurn: "Color Burn"
        case .softLight: "Soft Light"
        case .hardLight: "Hard Light"
        case .difference: "Difference"
        case .exclusion: "Exclusion"
        case .hue: "Hue"
        case .saturation: "Saturation"
        case .color: "Color"
        case .luminosity: "Luminosity"
        case .sourceAtop: "Source Atop"
        case .destinationOver: "Destination Over"
        case .destinationOut: "Destination Out"
        case .plusDarker: "Plus Darker"
        case .plusLighter: "Plus Lighter"
        }
    }

    public var blendMode: BlendMode {
        switch self {
        case .normal: .normal
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .darken: .darken
        case .lighten: .lighten
        case .colorDodge: .colorDodge
        case .colorBurn: .colorBurn
        case .softLight: .softLight
        case .hardLight: .hardLight
        case .difference: .difference
        case .exclusion: .exclusion
        case .hue: .hue
        case .saturation: .saturation
        case .color: .color
        case .luminosity: .luminosity
        case .sourceAtop: .sourceAtop
        case .destinationOver: .destinationOver
        case .destinationOut: .destinationOut
        case .plusDarker: .plusDarker
        case .plusLighter: .plusLighter
        }
    }
}
    
/// Shared state for playback controls debug settings
@MainActor
@Observable
public final class PlaybackControlsDebugState {
    public static let shared = PlaybackControlsDebugState()

    private static let blendModeKey = "PlaybackControls.blendMode"

    public var blendMode: DebugBlendMode {
        didSet {
            UserDefaults.standard.set(blendMode.rawValue, forKey: Self.blendModeKey)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.blendModeKey),
           let mode = DebugBlendMode(rawValue: saved) {
            self.blendMode = mode
        } else {
            self.blendMode = .colorDodge
        }
    }
}

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
