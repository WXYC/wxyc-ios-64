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
        case .perBandEMA: return "Per-Band (Auto)"
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
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let signalBoost = "visualizer.signalBoost"
        static let signalBoostEnabled = "visualizer.signalBoostEnabled"
        static let fftNormalizationMode = "visualizer.fftNormalizationMode"
        static let rmsNormalizationMode = "visualizer.rmsNormalizationMode"
        static let fftFrequencyWeighting = "visualizer.fftFrequencyWeighting"
        static let displayProcessor = "visualizer.displayProcessor"
        static let fftProcessingEnabled = "visualizer.fftProcessingEnabled"
        static let rmsProcessingEnabled = "visualizer.rmsProcessingEnabled"
        static let minBrightness = "visualizer.minBrightness"
        static let maxBrightness = "visualizer.maxBrightness"
        static let showFPS = "visualizer.showFPS"
    }
    
    // MARK: - Public Properties
    
    /// FFT magnitude values for visualization
    public private(set) var fftMagnitudes: [Float] = []
    
    /// RMS values per frequency bar
    public private(set) var rmsPerBar: [Float]
    
    /// Signal boost multiplier for amplifying visualization (1.0 = no boost)
    public var signalBoost: Float {
        get { _signalBoost }
        set {
            _signalBoost = max(0.1, min(newValue, 10.0))
            UserDefaults.standard.set(_signalBoost, forKey: Keys.signalBoost)
        }
    }
    
    /// Whether signal boost is applied (when false, boost is bypassed regardless of value)
    public var signalBoostEnabled: Bool = true {
        didSet { UserDefaults.standard.set(signalBoostEnabled, forKey: Keys.signalBoostEnabled) }
    }
    
    /// Normalization mode for FFT processor
    public var fftNormalizationMode: NormalizationMode = .none {
        didSet {
            fftProcessor.setNormalizationMode(fftNormalizationMode)
            UserDefaults.standard.set(fftNormalizationMode.rawValue, forKey: Keys.fftNormalizationMode)
        }
    }
    
    /// Frequency weighting exponent for FFT processor (compensates for natural roll-off)
    /// 0 = raw/bass-heavy, 0.5 = balanced, 1.0+ = treble-emphasized
    public var fftFrequencyWeighting: Float {
        get { _fftFrequencyWeighting }
        set {
            _fftFrequencyWeighting = max(0.0, min(newValue, 1.5))
            fftProcessor.setFrequencyWeightingExponent(_fftFrequencyWeighting)
            UserDefaults.standard.set(_fftFrequencyWeighting, forKey: Keys.fftFrequencyWeighting)
        }
    }
    
    /// Normalization mode for RMS processor
    public var rmsNormalizationMode: NormalizationMode = .ema {
        didSet {
            rmsProcessor.setNormalizationMode(rmsNormalizationMode)
            UserDefaults.standard.set(rmsNormalizationMode.rawValue, forKey: Keys.rmsNormalizationMode)
        }
    }
    
    /// Which processor's output to display in the visualizer
    /// Automatically enables the required processor(s) when changed
    public var displayProcessor: ProcessorType = .rms {
        didSet {
            UserDefaults.standard.set(displayProcessor.rawValue, forKey: Keys.displayProcessor)
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
        didSet { UserDefaults.standard.set(fftProcessingEnabled, forKey: Keys.fftProcessingEnabled) }
    }
    
    /// Whether RMS processing is enabled (saves CPU when disabled)
    public var rmsProcessingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(rmsProcessingEnabled, forKey: Keys.rmsProcessingEnabled) }
    }
    
    /// Minimum brightness for LCD segments (bottom segments)
    public var minBrightness: Double {
        get { _minBrightness }
        set {
            _minBrightness = max(0.0, min(newValue, _maxBrightness))
            UserDefaults.standard.set(_minBrightness, forKey: Keys.minBrightness)
        }
    }
    
    /// Maximum brightness for LCD segments (top segments)
    public var maxBrightness: Double {
        get { _maxBrightness }
        set {
            _maxBrightness = max(_minBrightness, min(newValue, 1.5))
            UserDefaults.standard.set(_maxBrightness, forKey: Keys.maxBrightness)
        }
    }
    
    /// Whether to show the FPS debug overlay
    public var showFPS: Bool = false {
        didSet { UserDefaults.standard.set(showFPS, forKey: Keys.showFPS) }
    }
    
    /// Legacy property for backwards compatibility - returns RMS mode
    @available(*, deprecated, message: "Use fftNormalizationMode or rmsNormalizationMode instead")
    public var normalizationMode: NormalizationMode {
        get { rmsNormalizationMode }
        set { rmsNormalizationMode = newValue }
    }
    
    // MARK: - Private Properties
    
    private var _signalBoost: Float = 1.0
    private var _fftFrequencyWeighting: Float = 0.5  // Default: balanced
    private var _minBrightness: Double = 0.90
    private var _maxBrightness: Double = 1.0
    private let rmsSmoothing: Float = 0.0  // No smoothing for maximum frame-to-frame sensitivity
    private let fftProcessor: FFTProcessor
    private let rmsProcessor: RMSProcessor
    
    // MARK: - Initialization
    
    public init() {
        self.rmsPerBar = Array(repeating: 0, count: VisualizerConstants.barAmount)
        self.fftProcessor = FFTProcessor(normalizationMode: .none)
        self.rmsProcessor = RMSProcessor(normalizationMode: .ema)
        
        // Load persisted settings
        loadPersistedSettings()
    }
    
    // MARK: - Persistence
    
    private func loadPersistedSettings() {
        let defaults = UserDefaults.standard
        
        // Signal boost
        if defaults.object(forKey: Keys.signalBoost) != nil {
            _signalBoost = defaults.float(forKey: Keys.signalBoost)
        }
        if defaults.object(forKey: Keys.signalBoostEnabled) != nil {
            signalBoostEnabled = defaults.bool(forKey: Keys.signalBoostEnabled)
        }
        
        // Normalization modes
        if let fftModeRaw = defaults.string(forKey: Keys.fftNormalizationMode),
           let fftMode = NormalizationMode(rawValue: fftModeRaw) {
            fftNormalizationMode = fftMode
            fftProcessor.setNormalizationMode(fftMode)
        }
        if let rmsModeRaw = defaults.string(forKey: Keys.rmsNormalizationMode),
           let rmsMode = NormalizationMode(rawValue: rmsModeRaw) {
            rmsNormalizationMode = rmsMode
            rmsProcessor.setNormalizationMode(rmsMode)
        }
        
        // Frequency weighting
        if defaults.object(forKey: Keys.fftFrequencyWeighting) != nil {
            _fftFrequencyWeighting = defaults.float(forKey: Keys.fftFrequencyWeighting)
            fftProcessor.setFrequencyWeightingExponent(_fftFrequencyWeighting)
        }
        
        // Display processor (also sets processing flags via didSet)
        if let displayRaw = defaults.string(forKey: Keys.displayProcessor),
           let display = ProcessorType(rawValue: displayRaw) {
            displayProcessor = display
        } else {
            // Apply default processing flags for default display mode (.rms)
            fftProcessingEnabled = false
            rmsProcessingEnabled = true
        }
        
        // Brightness - load directly to backing vars to avoid re-persisting
        if defaults.object(forKey: Keys.maxBrightness) != nil {
            _maxBrightness = defaults.double(forKey: Keys.maxBrightness)
        }
        if defaults.object(forKey: Keys.minBrightness) != nil {
            _minBrightness = defaults.double(forKey: Keys.minBrightness)
        }
        
        // Debug flags
        if defaults.object(forKey: Keys.showFPS) != nil {
            showFPS = defaults.bool(forKey: Keys.showFPS)
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
    
    /// Reset visualization state and persisted settings to defaults
    public func reset() {
        fftMagnitudes = []
        rmsPerBar = Array(repeating: 0, count: VisualizerConstants.barAmount)
        fftProcessor.reset()
        rmsProcessor.reset()
        
        // Reset persisted settings to defaults (use backing vars where available)
        _signalBoost = 1.0
        signalBoostEnabled = true
        fftNormalizationMode = .none
        fftFrequencyWeighting = 0.5  // Balanced
        rmsNormalizationMode = .ema
        // displayProcessor's didSet will set the processing flags appropriately
        displayProcessor = .rms
        _minBrightness = 0.90
        _maxBrightness = 1.0
        showFPS = false
        
        // Clear persisted values (will use defaults on next launch)
        clearPersistedSettings()
    }
    
    /// Sets the signal boost level
    public func setSignalBoost(_ boost: Float) {
        signalBoost = boost
    }
    
    /// Resets signal boost to default (no amplification)
    public func resetSignalBoost() {
        signalBoost = 1.0
    }
    
    /// Clears all persisted settings from UserDefaults
    private func clearPersistedSettings() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.signalBoost)
        defaults.removeObject(forKey: Keys.signalBoostEnabled)
        defaults.removeObject(forKey: Keys.fftNormalizationMode)
        defaults.removeObject(forKey: Keys.fftFrequencyWeighting)
        defaults.removeObject(forKey: Keys.rmsNormalizationMode)
        defaults.removeObject(forKey: Keys.displayProcessor)
        defaults.removeObject(forKey: Keys.fftProcessingEnabled)
        defaults.removeObject(forKey: Keys.rmsProcessingEnabled)
        defaults.removeObject(forKey: Keys.minBrightness)
        defaults.removeObject(forKey: Keys.maxBrightness)
        defaults.removeObject(forKey: Keys.showFPS)
    }
    
}

/// Legacy typealias for backwards compatibility
@available(*, deprecated, renamed: "VisualizerDataSource")
public typealias AudioVisualizer = VisualizerDataSource

