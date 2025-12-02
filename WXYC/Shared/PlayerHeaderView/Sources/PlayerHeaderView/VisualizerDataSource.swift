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
    public static let magnitudeLimit: Float = 32
    
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
    
    /// Normalization mode for adaptive level adjustment
    public var normalizationMode: NormalizationMode = .ema
    
    // MARK: - Private Properties
    
    private var _signalBoost: Float = 1.0
    private let rmsSmoothing: Float = 0.3
    private let bufferSize = 1024
    private var fftSetup: OpaquePointer?
    
    // MARK: - Adaptive Normalization (EMA)
    
    /// Separate running peaks for FFT and RMS (they're on different scales)
    private var runningPeakFFT: Float = 0.001
    private var runningPeakRMS: Float = 0.001
    
    /// Decay factor: ~1 minute half-life at 100Hz update rate
    private let peakDecay: Float = 0.99983
    
    /// Minimum floor to prevent extreme amplification
    private let normalizationFloor: Float = 0.001
    
    // MARK: - Adaptive Normalization (Circular Buffer)
    
    /// Circular buffers for tracking peak history (exact rolling window)
    private var peakHistoryFFT: [Float]
    private var peakHistoryRMS: [Float]
    private var peakHistoryIndexFFT = 0
    private var peakHistoryIndexRMS = 0
    
    // MARK: - Initialization
    
    public init() {
        self.rmsPerBar = Array(repeating: 0, count: VisualizerConstants.barAmount)
        self.peakHistoryFFT = Array(repeating: normalizationFloor, count: VisualizerConstants.peakHistorySize)
        self.peakHistoryRMS = Array(repeating: normalizationFloor, count: VisualizerConstants.peakHistorySize)
        setUpFFT()
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
    
    // MARK: - Setup
    
    private func setUpFFT() {
        fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            UInt(bufferSize),
            vDSP_DFT_Direction.FORWARD
        )
    }
    
    // MARK: - Public Methods
    
    /// Process an audio buffer for visualization
    /// Call this from the player's audio buffer callback (realtime audio thread)
    public func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0],
              let setup = fftSetup else { return }
        
        let frameLength = Int(buffer.frameLength)
        let boostedData: UnsafeMutablePointer<Float>
        let needsCleanup: Bool
        
        // Apply signal boost if needed
        if _signalBoost != 1.0 {
            boostedData = UnsafeMutablePointer<Float>.allocate(capacity: frameLength)
            var boost = _signalBoost
            vDSP_vsmul(channelData, 1, &boost, boostedData, 1, vDSP_Length(frameLength))
            needsCleanup = true
        } else {
            boostedData = channelData
            needsCleanup = false
        }
        
        let magnitudes = performFFT(data: boostedData, setup: setup)
        let rmsValues = computeRMSPerBar(data: boostedData, frameLength: frameLength)
        
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
        // Reset EMA peaks
        runningPeakFFT = normalizationFloor
        runningPeakRMS = normalizationFloor
        // Reset circular buffers
        peakHistoryFFT = Array(repeating: normalizationFloor, count: VisualizerConstants.peakHistorySize)
        peakHistoryRMS = Array(repeating: normalizationFloor, count: VisualizerConstants.peakHistorySize)
        peakHistoryIndexFFT = 0
        peakHistoryIndexRMS = 0
    }
    
    /// Sets the signal boost level
    public func setSignalBoost(_ boost: Float) {
        signalBoost = boost
    }
    
    /// Resets signal boost to default (no amplification)
    public func resetSignalBoost() {
        signalBoost = 1.0
    }
    
    // MARK: - Private Methods
    
    /// Normalize values using exponential moving average of peak
    /// - Parameters:
    ///   - values: The values to normalize (modified in place)
    ///   - runningPeak: The running peak to track (passed by reference)
    ///   - outputScale: Scale factor applied after normalization (default: magnitudeLimit)
    private func normalizeWithEMA(_ values: inout [Float], runningPeak: inout Float, outputScale: Float = VisualizerConstants.magnitudeLimit) {
        var currentPeak: Float = 0
        vDSP_maxv(values, 1, &currentPeak, vDSP_Length(values.count))
        
        // Update running peak: slow decay, instant rise
        runningPeak = max(currentPeak, runningPeak * peakDecay)
        runningPeak = max(runningPeak, normalizationFloor)
        
        // Normalize all values by the running peak (results in 0-1 range)
        vDSP_vsdiv(values, 1, &runningPeak, &values, 1, vDSP_Length(values.count))
        
        // Scale back up to expected visualization range
        var scale = outputScale
        vDSP_vsmul(values, 1, &scale, &values, 1, vDSP_Length(values.count))
    }
    
    /// Normalize values using a circular buffer for exact rolling window
    /// - Parameters:
    ///   - values: The values to normalize (modified in place)
    ///   - peakHistory: Circular buffer of peak values (passed by reference)
    ///   - historyIndex: Current write position in the buffer (passed by reference)
    ///   - outputScale: Scale factor applied after normalization (default: magnitudeLimit)
    private func normalizeWithCircularBuffer(_ values: inout [Float], peakHistory: inout [Float], historyIndex: inout Int, outputScale: Float = VisualizerConstants.magnitudeLimit) {
        var currentPeak: Float = 0
        vDSP_maxv(values, 1, &currentPeak, vDSP_Length(values.count))
        
        // Store current peak in circular buffer
        peakHistory[historyIndex] = max(currentPeak, normalizationFloor)
        historyIndex = (historyIndex + 1) % VisualizerConstants.peakHistorySize
        
        // Find max over the entire history window using vectorized operation
        var historyMax: Float = 0
        vDSP_maxv(peakHistory, 1, &historyMax, vDSP_Length(peakHistory.count))
        historyMax = max(historyMax, normalizationFloor)
        
        // Normalize all values by the historical max (results in 0-1 range)
        vDSP_vsdiv(values, 1, &historyMax, &values, 1, vDSP_Length(values.count))
        
        // Scale back up to expected visualization range
        var scale = outputScale
        vDSP_vsmul(values, 1, &scale, &values, 1, vDSP_Length(values.count))
    }
    
    /// Apply adaptive normalization based on current mode
    private func applyNormalization(_ values: inout [Float], isFFT: Bool) {
        switch normalizationMode {
        case .none:
            // No normalization - raw values pass through
            break
        case .ema:
            if isFFT {
                normalizeWithEMA(&values, runningPeak: &runningPeakFFT)
            } else {
                normalizeWithEMA(&values, runningPeak: &runningPeakRMS)
            }
        case .circularBuffer:
            if isFFT {
                normalizeWithCircularBuffer(&values, peakHistory: &peakHistoryFFT, historyIndex: &peakHistoryIndexFFT)
            } else {
                normalizeWithCircularBuffer(&values, peakHistory: &peakHistoryRMS, historyIndex: &peakHistoryIndexRMS)
            }
        }
    }
    
    private func computeRMSPerBar(data: UnsafeMutablePointer<Float>, frameLength: Int) -> [Float] {
        let samplesPerBar = frameLength / VisualizerConstants.barAmount
        var rmsValues = [Float](repeating: 0, count: VisualizerConstants.barAmount)
        
        for barIndex in 0..<VisualizerConstants.barAmount {
            let startSample = barIndex * samplesPerBar
            let endSample = min(startSample + samplesPerBar, frameLength)
            let sampleCount = endSample - startSample
            
            guard sampleCount > 0 else { continue }
            
            // Compute RMS: sqrt(mean(samples^2))
            var sumOfSquares: Float = 0
            vDSP_svesq(data.advanced(by: startSample), 1, &sumOfSquares, vDSP_Length(sampleCount))
            
            let meanSquare = sumOfSquares / Float(sampleCount)
            let rms = sqrt(meanSquare)
            
            // Scale RMS to a visible range
            rmsValues[barIndex] = rms * VisualizerConstants.magnitudeLimit * 2
        }
        
        applyNormalization(&rmsValues, isFFT: false)
        return rmsValues
    }
    
    private func performFFT(data: UnsafeMutablePointer<Float>, setup: OpaquePointer) -> [Float] {
        var realIn = [Float](repeating: 0, count: bufferSize)
        var imagIn = [Float](repeating: 0, count: bufferSize)
        var realOut = [Float](repeating: 0, count: bufferSize)
        var imagOut = [Float](repeating: 0, count: bufferSize)
        
        // Copy input data
        for i in 0..<bufferSize {
            realIn[i] = data[i]
        }
        
        // Perform DFT
        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)
        
        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: VisualizerConstants.barAmount)
        
        realOut.withUnsafeMutableBufferPointer { realBP in
            imagOut.withUnsafeMutableBufferPointer { imagBP in
                var complex = DSPSplitComplex(realp: realBP.baseAddress!, imagp: imagBP.baseAddress!)
                vDSP_zvabs(&complex, 1, &magnitudes, 1, UInt(VisualizerConstants.barAmount))
            }
        }
        
        // Normalize magnitudes
        var normalizedMagnitudes = [Float](repeating: 0.0, count: VisualizerConstants.barAmount)
        var scalingFactor = Float(1)
        vDSP_vsmul(&magnitudes, 1, &scalingFactor, &normalizedMagnitudes, 1, UInt(VisualizerConstants.barAmount))
        
        applyNormalization(&normalizedMagnitudes, isFFT: true)
        return normalizedMagnitudes
    }
}

/// Legacy typealias for backwards compatibility
@available(*, deprecated, renamed: "VisualizerDataSource")
public typealias AudioVisualizer = VisualizerDataSource

