//
//  VisualizerDataSource.swift
//  PlayerHeaderView
//
//  Processes audio buffers to produce FFT and RMS data for visualization
//  Separated from playback control as a dedicated observation layer
//

import Foundation
import AVFoundation
import Accelerate

/// Configuration constants for the audio visualizer
public enum VisualizerConstants {
    public static let updateInterval = 0.01
    public static let barAmount = 16
    public static let historyLength = 8
    public static let magnitudeLimit: Float = 64
    
    /// Size of circular buffer for rolling peak normalization
    /// At 100Hz (0.01s interval), 6000 samples = 1 minute window
    public static let peakHistorySize = 6000
}

/// Normalization mode for adaptive audio visualization
public enum NormalizationMode: Sendable, CaseIterable {
    /// No adaptive normalization - raw values pass through
    case none
    /// Exponential moving average - smooth transitions, approximate window
    case ema
    /// Circular buffer - exact window, may have step changes when peaks exit
    case circularBuffer
    
    /// Returns the next mode in the cycle
    public var next: NormalizationMode {
        let all = Self.allCases
        let currentIndex = all.firstIndex(of: self)!
        let nextIndex = (currentIndex + 1) % all.count
        return all[nextIndex]
    }
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .ema: return "EMA"
        case .circularBuffer: return "Circular Buffer"
        }
    }
}

/// Which processor's output to display
public enum ProcessorType: Sendable, CaseIterable {
    case fft
    case rms
    case both  // Show both side-by-side (for comparison)
    
    public var displayName: String {
        switch self {
        case .fft: return "FFT"
        case .rms: return "RMS"
        case .both: return "Both"
        }
    }
}

/// Processes audio buffers to produce FFT magnitudes and RMS values for visualization.
/// Note: Not @MainActor because processBuffer is called from realtime audio thread.
/// Observable property updates are dispatched to MainActor internally.
@Observable
public final class VisualizerDataSource: @unchecked Sendable {
    
    // MARK: - Public Properties
    
    /// FFT magnitude values for visualization
    public private(set) var fftMagnitudes: [Float] = []
    
    /// RMS values per frequency bar
    public private(set) var rmsPerBar: [Float]
    
    /// Signal boost multiplier for amplifying visualization (1.0 = no boost)
    public var signalBoost: Float {
        get { _signalBoost }
        set { _signalBoost = max(0.1, min(newValue, 10.0)) }
    }
    
    /// Whether signal boost is applied (when false, boost is bypassed regardless of value)
    public var signalBoostEnabled: Bool = true
    
    /// Normalization mode for FFT processor
    public var fftNormalizationMode: NormalizationMode = .none {
        didSet {
            fftProcessor.setNormalizationMode(fftNormalizationMode)
        }
    }
    
    /// Normalization mode for RMS processor
    public var rmsNormalizationMode: NormalizationMode = .ema {
        didSet {
            rmsProcessor.setNormalizationMode(rmsNormalizationMode)
        }
    }
    
    /// Which processor's output to display in the visualizer
    public var displayProcessor: ProcessorType = .rms
    
    /// Whether FFT processing is enabled (saves CPU when disabled)
    public var fftProcessingEnabled: Bool = true
    
    /// Whether RMS processing is enabled (saves CPU when disabled)
    public var rmsProcessingEnabled: Bool = true
    
    /// Minimum brightness for LCD segments (bottom segments)
    public var minBrightness: Double = 0.90 {
        didSet { minBrightness = max(0.0, min(minBrightness, maxBrightness)) }
    }
    
    /// Maximum brightness for LCD segments (top segments)
    public var maxBrightness: Double = 1.0 {
        didSet { maxBrightness = max(minBrightness, min(maxBrightness, 1.5)) }
    }
    
    /// Legacy property for backwards compatibility - returns RMS mode
    @available(*, deprecated, message: "Use fftNormalizationMode or rmsNormalizationMode instead")
    public var normalizationMode: NormalizationMode {
        get { rmsNormalizationMode }
        set { rmsNormalizationMode = newValue }
    }
    
    // MARK: - Private Properties
    
    private var _signalBoost: Float = 1.0
    private let rmsSmoothing: Float = 0.0  // No smoothing for maximum frame-to-frame sensitivity
    private let fftProcessor: FFTProcessor
    private let rmsProcessor: RMSProcessor
    
    // MARK: - Initialization
    
    public init() {
        self.rmsPerBar = Array(repeating: 0, count: VisualizerConstants.barAmount)
        self.fftProcessor = FFTProcessor(normalizationMode: .none)
        self.rmsProcessor = RMSProcessor(normalizationMode: .ema)
    }
    
    // MARK: - Public Methods
    
    /// Process an audio buffer for visualization
    /// Call this from the player's audio buffer callback (realtime audio thread)
    public func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        let boostedData: UnsafeMutablePointer<Float>
        let needsCleanup: Bool
        
        // Apply signal boost if enabled and needed
        if signalBoostEnabled && _signalBoost != 1.0 {
            boostedData = UnsafeMutablePointer<Float>.allocate(capacity: frameLength)
            var boost = _signalBoost
            vDSP_vsmul(channelData, 1, &boost, boostedData, 1, vDSP_Length(frameLength))
            needsCleanup = true
        } else {
            boostedData = channelData
            needsCleanup = false
        }
        
        var magnitudes: [Float] = []
        var rmsValues: [Float] = []
        
        if fftProcessingEnabled {
            magnitudes = fftProcessor.process(data: boostedData, frameLength: frameLength)
        }
        if rmsProcessingEnabled {
            rmsValues = rmsProcessor.process(data: boostedData, frameLength: frameLength)
        }
        
        if needsCleanup {
            boostedData.deallocate()
        }
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.fftMagnitudes = magnitudes
            
            // Apply smoothing: blend new RMS with previous values
            for i in 0..<VisualizerConstants.barAmount {
                let newValue = i < rmsValues.count ? rmsValues[i] : 0
                self.rmsPerBar[i] = self.rmsSmoothing * self.rmsPerBar[i] + (1 - self.rmsSmoothing) * newValue
            }
        }
    }
    
    /// Reset visualization state
    public func reset() {
        fftMagnitudes = []
        rmsPerBar = Array(repeating: 0, count: VisualizerConstants.barAmount)
        fftProcessor.reset()
        rmsProcessor.reset()
    }
    
    /// Sets the signal boost level
    public func setSignalBoost(_ boost: Float) {
        signalBoost = boost
    }
    
    /// Resets signal boost to default (no amplification)
    public func resetSignalBoost() {
        signalBoost = 1.0
    }
    
}

/// Legacy typealias for backwards compatibility
@available(*, deprecated, renamed: "VisualizerDataSource")
public typealias AudioVisualizer = VisualizerDataSource

