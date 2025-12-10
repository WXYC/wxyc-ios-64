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
import ObservableDefaults

/// Configuration constants for the audio visualizer
enum VisualizerConstants {
    static let updateInterval = 0.01
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
@ObservableDefaults(autoInit: false)
public final class VisualizerDataSource: @unchecked Sendable {
    
    // MARK: - Observable Output (not persisted)
    
    /// FFT magnitude values for visualization
    @ObservableOnly
    public var fftMagnitudes: [Float] = []
    
    /// RMS values per frequency bar
    @ObservableOnly
    public var rmsPerBar: [Float] = Array(repeating: 0, count: VisualizerConstants.barAmount)
    
    // MARK: - Persisted Settings
    
    /// Signal boost multiplier for amplifying visualization (1.0 = no boost)
    @DefaultsKey(userDefaultsKey: "visualizer.signalBoost")
    public var signalBoost: Float = 1.0
    
    /// Whether signal boost is applied (when false, boost is bypassed regardless of value)
    @DefaultsKey(userDefaultsKey: "visualizer.signalBoostEnabled")
    public var signalBoostEnabled: Bool = true
    
    /// Normalization mode for FFT processor
    @DefaultsKey(userDefaultsKey: "visualizer.fftNormalizationMode")
    public var fftNormalizationMode: NormalizationMode = .perBandEMA {
        didSet { fftProcessor.setNormalizationMode(fftNormalizationMode) }
    }
    
    /// Frequency weighting exponent for FFT processor (compensates for natural roll-off)
    /// 0 = raw/bass-heavy, 0.5 = balanced, 1.0+ = treble-emphasized
    @DefaultsKey(userDefaultsKey: "visualizer.fftFrequencyWeighting")
    public var fftFrequencyWeighting: Float = 1.0 {
        didSet { fftProcessor.setFrequencyWeightingExponent(fftFrequencyWeighting) }
    }
    
    /// Normalization mode for RMS processor
    @DefaultsKey(userDefaultsKey: "visualizer.rmsNormalizationMode")
    public var rmsNormalizationMode: NormalizationMode = .ema {
        didSet { rmsProcessor.setNormalizationMode(rmsNormalizationMode) }
    }
    
    /// Which processor's output to display in the visualizer
    /// Automatically enables the required processor(s) when changed
    @DefaultsKey(userDefaultsKey: "visualizer.displayProcessor")
    public var displayProcessor: ProcessorType = .fft {
        didSet {
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
    @DefaultsKey(userDefaultsKey: "visualizer.fftProcessingEnabled")
    public var fftProcessingEnabled: Bool = true
    
    /// Whether RMS processing is enabled (saves CPU when disabled)
    @DefaultsKey(userDefaultsKey: "visualizer.rmsProcessingEnabled")
    public var rmsProcessingEnabled: Bool = true
    
    /// Minimum brightness for LCD segments (bottom segments)
    @DefaultsKey(userDefaultsKey: "visualizer.minBrightness")
    public var minBrightness: Double = 0.90
    
    /// Maximum brightness for LCD segments (top segments)
    @DefaultsKey(userDefaultsKey: "visualizer.maxBrightness")
    public var maxBrightness: Double = 1.0
    
    /// Whether to show the FPS debug overlay
    @DefaultsKey(userDefaultsKey: "visualizer.showFPS")
    public var showFPS: Bool = false
    
    // MARK: - Private Properties (not persisted)
    
    @Ignore
    private let rmsSmoothing: Float = 0.0  // No smoothing for maximum frame-to-frame sensitivity
    
    @Ignore
    private let fftProcessor: FFTProcessor
    
    @Ignore
    private let rmsProcessor: RMSProcessor
    
    // MARK: - Initialization
    
    public init() {
        // Read persisted values directly from UserDefaults before self is fully initialized
        // (property wrappers aren't accessible until after init completes)
        let storedNormMode = UserDefaults.standard.string(forKey: "visualizer.fftNormalizationMode")
            .flatMap { NormalizationMode(rawValue: $0) } ?? .perBandEMA
        let storedWeighting = UserDefaults.standard.object(forKey: "visualizer.fftFrequencyWeighting") as? Float ?? 1.0
        let storedRmsNormMode = UserDefaults.standard.string(forKey: "visualizer.rmsNormalizationMode")
            .flatMap { NormalizationMode(rawValue: $0) } ?? .ema
        
        self.fftProcessor = FFTProcessor(
            normalizationMode: storedNormMode,
            frequencyWeightingExponent: storedWeighting
        )
        self.rmsProcessor = RMSProcessor(normalizationMode: storedRmsNormMode)
        
        // Start listening for UserDefaults changes (required by ObservableDefaults)
        observerStarter()
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
        minBrightness = 0.90
        maxBrightness = 1.0
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
