//
//  Normalizer.swift
//  PlayerHeaderView
//
//  Normalization algorithms for adaptive audio visualization
//

import Foundation
import Accelerate

/// Protocol for normalization algorithms that adapt visualization levels
protocol Normalizer: Sendable {
    /// Normalize values in place
    /// - Parameters:
    ///   - values: The values to normalize (modified in place)
    ///   - outputScale: Scale factor applied after normalization
    func normalize(_ values: inout [Float], outputScale: Float)
    
    /// Reset normalization state
    func reset()
}

/// No normalization - values pass through unchanged
final class NoNormalizer: @unchecked Sendable, Normalizer {
    func normalize(_ values: inout [Float], outputScale: Float) {
        // No-op: values remain unchanged
    }
    
    func reset() {
        // No state to reset
    }
}

/// Exponential moving average normalization
/// Provides smooth transitions with approximate window size
/// Note: @unchecked Sendable because mutable state is protected by Mutex in the processors
final class EMANormalizer: @unchecked Sendable, Normalizer {
    private var runningPeak: Float = 0.001
    private let peakDecay: Float = 0.99983  // ~1 minute half-life at 100Hz update rate
    private let normalizationFloor: Float = 0.001
    
    func normalize(_ values: inout [Float], outputScale: Float) {
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
    
    func reset() {
        runningPeak = normalizationFloor
    }
}

/// Circular buffer normalization with exact rolling window
/// Provides exact window size but may have step changes when peaks exit
/// Note: @unchecked Sendable because mutable state is protected by Mutex in the processors
final class CircularBufferNormalizer: @unchecked Sendable, Normalizer {
    private var peakHistory: [Float]
    private var historyIndex = 0
    private let normalizationFloor: Float = 0.001
    
    init() {
        self.peakHistory = Array(repeating: normalizationFloor, count: VisualizerConstants.peakHistorySize)
    }
    
    func normalize(_ values: inout [Float], outputScale: Float) {
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
    
    func reset() {
        peakHistory = Array(repeating: normalizationFloor, count: VisualizerConstants.peakHistorySize)
        historyIndex = 0
    }
}

/// Per-band EMA normalization - each frequency band has its own peak tracker
/// This automatically balances the visualization across all frequencies regardless of content.
/// Bass-heavy music won't dominate; quiet high frequencies will be boosted relative to their own history.
/// Note: @unchecked Sendable because mutable state is protected by Mutex in the processors
final class PerBandEMANormalizer: @unchecked Sendable, Normalizer {
    private var runningPeaks: [Float]
    private let peakDecay: Float = 0.9997  // Slightly faster decay than global EMA (~30s half-life at 100Hz)
    private let normalizationFloor: Float = 0.001
    
    init(bandCount: Int = VisualizerConstants.barAmount) {
        self.runningPeaks = Array(repeating: 0.001, count: bandCount)
    }
    
    func normalize(_ values: inout [Float], outputScale: Float) {
        let count = min(values.count, runningPeaks.count)
        
        for i in 0..<count {
            // Update per-band running peak: slow decay, instant rise
            runningPeaks[i] = max(values[i], runningPeaks[i] * peakDecay)
            runningPeaks[i] = max(runningPeaks[i], normalizationFloor)
            
            // Normalize this band by its own running peak
            values[i] = (values[i] / runningPeaks[i]) * outputScale
        }
    }
    
    func reset() {
        for i in 0..<runningPeaks.count {
            runningPeaks[i] = normalizationFloor
        }
    }
}

extension NormalizationMode {
    /// Create a normalizer instance for this mode
    func createNormalizer() -> any Normalizer {
        switch self {
        case .none:
            return NoNormalizer()
        case .ema:
            return EMANormalizer()
        case .circularBuffer:
            return CircularBufferNormalizer()
        case .perBandEMA:
            return PerBandEMANormalizer()
        }
    }
}

