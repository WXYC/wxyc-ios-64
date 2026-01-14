//
//  FFTProcessor.swift
//  PlayerHeaderView
//
//  Fast Fourier Transform processor for frequency domain visualization
//
//  Created by Jake Bromberg on 12/02/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Accelerate
import Synchronization

/// Fast Fourier Transform processor for frequency domain visualization
/// Note: @unchecked Sendable because it's primarily accessed from the single-threaded audio processing context.
/// The normalizer property is protected with Mutex for thread-safe access when normalization mode changes from MainActor.
final class FFTProcessor: @unchecked Sendable, AudioProcessor {
    private let bufferSize = 2048  // Larger buffer for better frequency resolution
    private var fftSetup: OpaquePointer?
    private let normalizerMutex: Mutex<any Normalizer>
    
    /// Pre-computed Hann window to reduce spectral leakage
    private let hannWindow: [Float]
    
    /// Pre-computed logarithmic band boundaries (FFT bin indices)
    /// Each bar covers bins from bandBoundaries[i] to bandBoundaries[i+1]-1
    private let bandBoundaries: [Int]
    
    /// Minimum FFT bin (used for gain calculations)
    private let minBin: Int
    
    /// Per-band gain to compensate for natural frequency roll-off
    /// Music naturally has more energy at low frequencies; this boosts higher bands
    /// Protected by mutex for thread-safe updates when weighting mode changes
    private let bandGainsMutex: Mutex<[Float]>
    
    /// - Parameters:
    ///   - normalizationMode: How to normalize FFT magnitudes for display
    ///   - frequencyWeightingExponent: Exponent for frequency compensation (0 = raw/bass-heavy, 0.5 = balanced, 1.0 = treble-emphasized)
    init(normalizationMode: NormalizationMode, frequencyWeightingExponent: Float) {
        self.normalizerMutex = Mutex(normalizationMode.createNormalizer())
        
        // Create Hann window: w[n] = 0.5 * (1 - cos(2πn / N))
        // This reduces spectral leakage by tapering the signal at the edges
        var window = [Float](repeating: 0, count: bufferSize)
        vDSP_hann_window(&window, vDSP_Length(bufferSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
        
        // Pre-compute logarithmic frequency band boundaries
        // Maps barAmount bars to FFT bins with logarithmic spacing
        let fftBins = bufferSize / 2  // Usable bins (Nyquist bin excluded)
        let barCount = VisualizerConstants.barAmount
        
        // Define frequency range: ~30Hz to ~16kHz (assuming 44.1kHz sample rate)
        // Bin frequency = bin_index * sample_rate / bufferSize
        // For 44100Hz and 2048 samples: each bin ≈ 21.5Hz
        let minBin = 2      // ~43Hz - skip DC and very low frequencies
        let maxBin = fftBins - 1  // Up to Nyquist
        self.minBin = minBin
        
        var boundaries = [Int]()
        let logMin = log(Float(minBin))
        let logMax = log(Float(maxBin))
        
        for i in 0...barCount {
            let logBin = logMin + (logMax - logMin) * Float(i) / Float(barCount)
            let bin = Int(exp(logBin))
            boundaries.append(min(max(bin, minBin), maxBin))
        }
        self.bandBoundaries = boundaries
        
        // Compute initial band gains based on weighting exponent
        let gains = Self.computeBandGains(
            boundaries: boundaries,
            minBin: minBin,
            exponent: frequencyWeightingExponent
        )
        self.bandGainsMutex = Mutex(gains)
        
        setUpFFT()
    }
    
    /// Compute per-band gains for the given frequency weighting exponent
    /// - Parameters:
    ///   - boundaries: Pre-computed FFT bin boundaries for each bar
    ///   - minBin: Minimum FFT bin (reference for frequency ratio)
    ///   - exponent: Weighting exponent (0 = no boost, 0.5 = sqrt/balanced, 1.0 = linear/max boost)
    private static func computeBandGains(
        boundaries: [Int],
        minBin: Int,
        exponent: Float
    ) -> [Float] {
        let barCount = VisualizerConstants.barAmount
        var gains = [Float](repeating: 1.0, count: barCount)
        
        guard exponent > 0 else { return gains }
        
        for i in 0..<barCount {
            let centerBin = (boundaries[i] + boundaries[i + 1]) / 2
            let frequencyRatio = Float(centerBin) / Float(minBin)
            gains[i] = pow(frequencyRatio, exponent)
        }
        
        return gains
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
    
    func process(data: UnsafeMutablePointer<Float>, frameLength: Int) -> [Float] {
        guard let setup = fftSetup else { return Array(repeating: 0, count: VisualizerConstants.barAmount) }
        
        // Ensure we have enough data (pad with zeros if needed, or truncate)
        let samplesToUse = min(frameLength, bufferSize)
        
        var realIn = [Float](repeating: 0, count: bufferSize)
        var imagIn = [Float](repeating: 0, count: bufferSize)
        var realOut = [Float](repeating: 0, count: bufferSize)
        var imagOut = [Float](repeating: 0, count: bufferSize)
        
        // Copy input data and apply Hann window to reduce spectral leakage
        // The window tapers the signal to zero at the edges, preventing discontinuities
        // that cause energy to spread across frequency bins
        for i in 0..<samplesToUse {
            realIn[i] = data[i] * hannWindow[i]
        }
        
        // Perform DFT
        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)
        
        // Calculate magnitudes for FFT bins (only need first half + 1 for real input)
        let fftBins = bufferSize / 2 + 1
        var allMagnitudes = [Float](repeating: 0, count: fftBins)
        realOut.withUnsafeMutableBufferPointer { realBP in
            imagOut.withUnsafeMutableBufferPointer { imagBP in
                var complex = DSPSplitComplex(realp: realBP.baseAddress!, imagp: imagBP.baseAddress!)
                vDSP_zvabs(&complex, 1, &allMagnitudes, 1, UInt(fftBins))
            }
        }
        
        // Map FFT bins to visualization bars using pre-computed logarithmic boundaries
        // Each bar averages the magnitudes in its frequency band, then applies gain compensation
        var magnitudes = [Float](repeating: 0, count: VisualizerConstants.barAmount)
        
        for barIndex in 0..<VisualizerConstants.barAmount {
            let startBin = bandBoundaries[barIndex]
            let endBin = bandBoundaries[barIndex + 1]
            
            var bandMagnitude: Float
            if endBin > startBin {
                // Average magnitudes in this frequency band
                var sum: Float = 0
                let count = endBin - startBin
                vDSP_sve(Array(allMagnitudes[startBin..<endBin]), 1, &sum, vDSP_Length(count))
                bandMagnitude = sum / Float(count)
            } else {
                // Band has only one bin - use it directly
                bandMagnitude = allMagnitudes[startBin]
            }
            
            magnitudes[barIndex] = bandMagnitude
        }
        
        // Apply per-band gain compensation for natural frequency roll-off (thread-safe access)
        bandGainsMutex.withLock { bandGains in
            for i in 0..<VisualizerConstants.barAmount {
                magnitudes[i] *= bandGains[i]
            }
        }
        
        // Apply normalization (thread-safe access)
        normalizerMutex.withLock { normalizer in
            normalizer.normalize(&magnitudes, outputScale: VisualizerConstants.magnitudeLimit)
        }
        
        return magnitudes
    }
    
    func reset() {
        normalizerMutex.withLock { normalizer in
            normalizer.reset()
        }
    }
    
    func setNormalizationMode(_ mode: NormalizationMode) {
        normalizerMutex.withLock { normalizer in
            normalizer = mode.createNormalizer()
        }
    }
    
    /// Update the frequency weighting exponent
    /// - Parameter exponent: Weighting exponent (0 = no boost, 0.5 = balanced, 1.0 = max boost)
    func setFrequencyWeightingExponent(_ exponent: Float) {
        let newGains = Self.computeBandGains(
            boundaries: bandBoundaries,
            minBin: minBin,
            exponent: exponent
        )
        bandGainsMutex.withLock { bandGains in
            bandGains = newGains
        }
    }
    
    // MARK: - Private Methods
    
    private func setUpFFT() {
        fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            UInt(bufferSize),
            vDSP_DFT_Direction.FORWARD
        )
    }
}
