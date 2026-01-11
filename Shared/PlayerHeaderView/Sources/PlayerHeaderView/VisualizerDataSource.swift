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
enum VisualizerConstants {
    static let updateInterval = 1.0 / 60.0
    static let barAmount = 16
    static let historyLength = 8
    static let magnitudeLimit: Float = 64
    
    /// Size of circular buffer for rolling peak normalization
    /// At 100Hz (0.01s interval), 6000 samples = 1 minute window
    static let peakHistorySize = 6000
}

/// Normalization mode for adaptive audio visualization
public enum NormalizationMode: String, Sendable, CaseIterable, Hashable {
    /// No adaptive normalization - raw values pass through
    case none
    /// Exponential moving average - smooth transitions, approximate window
    case ema
    /// Circular buffer - exact window, may have step changes when peaks exit
    case circularBuffer
    /// Per-band EMA - each frequency band normalized independently (auto-balances frequencies)
    case perBandEMA
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .none: "None"
        case .ema: "EMA"
        case .circularBuffer: "Circular Buffer"
        case .perBandEMA: "Per-Band (Auto)"
        }
    }
}

/// Which processor's output to display
public enum ProcessorType: String, Sendable, CaseIterable, Hashable {
    case fft
    case rms
    case both  // Show both side-by-side (for comparison)
    
    public var displayName: String {
        switch self {
        case .fft: "FFT"
        case .rms: "RMS"
        case .both: "Both"
        }
    }
}

/// Processes audio buffers to produce FFT magnitudes and RMS values for visualization.
/// Note: Not @MainActor because processBuffer is called from realtime audio thread.
/// Observable property updates are dispatched to MainActor internally.
@Observable
public final class VisualizerDataSource: @unchecked Sendable {

    // MARK: - UserDefaults Keys

    private enum DefaultsKeys {
        static let signalBoost = "visualizer.signalBoost"
        static let signalBoostEnabled = "visualizer.signalBoostEnabled"
        static let fftNormalizationMode = "visualizer.fftNormalizationMode"
        static let fftFrequencyWeighting = "visualizer.fftFrequencyWeighting"
        static let rmsNormalizationMode = "visualizer.rmsNormalizationMode"
        static let displayProcessor = "visualizer.displayProcessor"
        static let fftProcessingEnabled = "visualizer.fftProcessingEnabled"
        static let rmsProcessingEnabled = "visualizer.rmsProcessingEnabled"
        static let showFPS = "visualizer.showFPS"
    }

    // MARK: - Observable Output (not persisted)

    /// FFT magnitude values for visualization
    public var fftMagnitudes: [Float] = []

    /// RMS values per frequency bar
    public var rmsPerBar: [Float] = Array(repeating: 0, count: VisualizerConstants.barAmount)

    // MARK: - Persisted Settings

    /// Signal boost multiplier for amplifying visualization (1.0 = no boost, range: 0.1–10.0)
    public var signalBoost: Float = 1.0 {
        didSet {
            let clamped = max(0.1, min(signalBoost, 10.0))
            if signalBoost != clamped {
                signalBoost = clamped
            } else {
                UserDefaults.standard.set(signalBoost, forKey: DefaultsKeys.signalBoost)
            }
        }
    }

    /// Whether signal boost is applied (when false, boost is bypassed regardless of value)
    public var signalBoostEnabled: Bool = true {
        didSet { UserDefaults.standard.set(signalBoostEnabled, forKey: DefaultsKeys.signalBoostEnabled) }
    }

    /// Normalization mode for FFT processor
    public var fftNormalizationMode: NormalizationMode = .perBandEMA {
        didSet {
            UserDefaults.standard.set(fftNormalizationMode.rawValue, forKey: DefaultsKeys.fftNormalizationMode)
            fftProcessor.setNormalizationMode(fftNormalizationMode)
        }
    }

    /// Frequency weighting exponent for FFT processor (compensates for natural roll-off)
    /// 0 = raw/bass-heavy, 0.5 = balanced, 1.0+ = treble-emphasized
    public var fftFrequencyWeighting: Float = 1.0 {
        didSet {
            UserDefaults.standard.set(fftFrequencyWeighting, forKey: DefaultsKeys.fftFrequencyWeighting)
            fftProcessor.setFrequencyWeightingExponent(fftFrequencyWeighting)
        }
    }

    /// Normalization mode for RMS processor
    public var rmsNormalizationMode: NormalizationMode = .ema {
        didSet {
            UserDefaults.standard.set(rmsNormalizationMode.rawValue, forKey: DefaultsKeys.rmsNormalizationMode)
            rmsProcessor.setNormalizationMode(rmsNormalizationMode)
        }
    }

    /// Which processor's output to display in the visualizer
    /// Automatically enables the required processor(s) when changed
    public var displayProcessor: ProcessorType = .fft {
        didSet {
            UserDefaults.standard.set(displayProcessor.rawValue, forKey: DefaultsKeys.displayProcessor)
            // Auto-enable required processors, disable unused ones to save CPU
            switch displayProcessor {
            case .fft:
                fftProcessingEnabled = true
                rmsProcessingEnabled = false
            case .rms:
                fftProcessingEnabled = false
                rmsProcessingEnabled = true
            case .both:
                fftProcessingEnabled = true
                rmsProcessingEnabled = true
            }
        }
    }

    /// Whether FFT processing is enabled (saves CPU when disabled)
    public var fftProcessingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(fftProcessingEnabled, forKey: DefaultsKeys.fftProcessingEnabled) }
    }

    /// Whether RMS processing is enabled (saves CPU when disabled)
    public var rmsProcessingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(rmsProcessingEnabled, forKey: DefaultsKeys.rmsProcessingEnabled) }
    }

    /// Whether to show the FPS debug overlay
    public var showFPS: Bool = false {
        didSet { UserDefaults.standard.set(showFPS, forKey: DefaultsKeys.showFPS) }
    }

    // MARK: - Private Properties (not persisted)

    @ObservationIgnored
    private let rmsSmoothing: Float = 0.0  // No smoothing for maximum frame-to-frame sensitivity

    @ObservationIgnored
    private let fftProcessor: FFTProcessor

    @ObservationIgnored
    private let rmsProcessor: RMSProcessor
    
    // MARK: - Initialization

    public init() {
        let defaults = UserDefaults.standard

        // Load persisted values from UserDefaults
        let storedNormMode = defaults.string(forKey: DefaultsKeys.fftNormalizationMode)
            .flatMap { NormalizationMode(rawValue: $0) } ?? .perBandEMA
        let storedWeighting = defaults.object(forKey: DefaultsKeys.fftFrequencyWeighting) as? Float ?? 1.0
        let storedRmsNormMode = defaults.string(forKey: DefaultsKeys.rmsNormalizationMode)
            .flatMap { NormalizationMode(rawValue: $0) } ?? .ema
    
        // Initialize processors with stored values
        self.fftProcessor = FFTProcessor(
            normalizationMode: storedNormMode,
            frequencyWeightingExponent: storedWeighting
        )
        self.rmsProcessor = RMSProcessor(normalizationMode: storedRmsNormMode)

        // Load all other persisted settings
        if let boost = defaults.object(forKey: DefaultsKeys.signalBoost) as? Float {
            self.signalBoost = boost
        }
        if defaults.object(forKey: DefaultsKeys.signalBoostEnabled) != nil {
            self.signalBoostEnabled = defaults.bool(forKey: DefaultsKeys.signalBoostEnabled)
        }
        self.fftNormalizationMode = storedNormMode
        self.fftFrequencyWeighting = storedWeighting
        self.rmsNormalizationMode = storedRmsNormMode
        if let displayRaw = defaults.string(forKey: DefaultsKeys.displayProcessor),
           let processor = ProcessorType(rawValue: displayRaw) {
            self.displayProcessor = processor
        }
        if defaults.object(forKey: DefaultsKeys.fftProcessingEnabled) != nil {
            self.fftProcessingEnabled = defaults.bool(forKey: DefaultsKeys.fftProcessingEnabled)
        }
        if defaults.object(forKey: DefaultsKeys.rmsProcessingEnabled) != nil {
            self.rmsProcessingEnabled = defaults.bool(forKey: DefaultsKeys.rmsProcessingEnabled)
        }
        if defaults.object(forKey: DefaultsKeys.showFPS) != nil {
            self.showFPS = defaults.bool(forKey: DefaultsKeys.showFPS)
        }
    }
        
    // MARK: - Public Methods
    
    /// Process an audio buffer for visualization
    /// Call this from the player's audio buffer callback (realtime audio thread)
    public func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        let boostedData: UnsafeMutablePointer<Float>
        let needsCleanup: Bool
        
        // Apply signal boost if enabled and needed (clamp to valid range)
        let clampedBoost = max(0.1, min(signalBoost, 10.0))
        if signalBoostEnabled && clampedBoost != 1.0 {
            boostedData = UnsafeMutablePointer<Float>.allocate(capacity: frameLength)
            var boost = clampedBoost
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
        
    /// Reset visualization state and persisted settings to defaults
    public func reset() {
        fftMagnitudes = []
        rmsPerBar = Array(repeating: 0, count: VisualizerConstants.barAmount)
        fftProcessor.reset()
        rmsProcessor.reset()
        
        // Reset persisted settings to defaults
        signalBoost = 1.0
        signalBoostEnabled = true
        fftNormalizationMode = .none
        fftFrequencyWeighting = 0.5
        rmsNormalizationMode = .ema
        // displayProcessor's didSet will set the processing flags appropriately
        displayProcessor = .rms
        showFPS = false
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
