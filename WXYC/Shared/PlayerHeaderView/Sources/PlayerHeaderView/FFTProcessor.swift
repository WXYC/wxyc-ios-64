//
//  FFTProcessor.swift
//  PlayerHeaderView
//
//  Fast Fourier Transform processor for frequency domain visualization
//

import Foundation
import Accelerate
import Synchronization

/// Fast Fourier Transform processor for frequency domain visualization
/// Note: @unchecked Sendable because it's primarily accessed from the single-threaded audio processing context.
/// The normalizer property is protected with Mutex for thread-safe access when normalization mode changes from MainActor.
final class FFTProcessor: @unchecked Sendable, AudioProcessor {
    private let bufferSize = 1024
    private var fftSetup: OpaquePointer?
    private let normalizerMutex: Mutex<any Normalizer>
    
    init(normalizationMode: NormalizationMode = .ema) {
        self.normalizerMutex = Mutex(normalizationMode.createNormalizer())
        setUpFFT()
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
        
        // Copy input data (only up to available samples, rest stays zero)
        for i in 0..<samplesToUse {
            realIn[i] = data[i]
        }
        
        // Perform DFT
        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)
        
        // For real input FFT, we get bufferSize/2 + 1 unique frequency bins
        // Map these to our barAmount bars using logarithmic spacing for better frequency representation
        let fftBins = bufferSize / 2 + 1
        var magnitudes = [Float](repeating: 0, count: VisualizerConstants.barAmount)
        
        // Calculate magnitudes for all FFT bins first
        var allMagnitudes = [Float](repeating: 0, count: fftBins)
        realOut.withUnsafeMutableBufferPointer { realBP in
            imagOut.withUnsafeMutableBufferPointer { imagBP in
                var complex = DSPSplitComplex(realp: realBP.baseAddress!, imagp: imagBP.baseAddress!)
                vDSP_zvabs(&complex, 1, &allMagnitudes, 1, UInt(fftBins))
            }
        }
        
        // Map FFT bins to visualization bars using logarithmic spacing
        // This gives better frequency representation (lower frequencies get more bars)
        if VisualizerConstants.barAmount > 1 {
            for barIndex in 0..<VisualizerConstants.barAmount {
                // Logarithmic mapping: map bar index to FFT bin index
                let logStart: Float = 0
                let logEnd = log2(Float(fftBins))
                let logPosition = logStart + (logEnd - logStart) * Float(barIndex) / Float(VisualizerConstants.barAmount - 1)
                let fftBinIndex = Int(pow(2, Double(logPosition)))
                
                // Clamp to valid range and take the magnitude
                let clampedIndex = min(fftBinIndex, fftBins - 1)
                magnitudes[barIndex] = allMagnitudes[clampedIndex]
            }
        } else if VisualizerConstants.barAmount == 1 {
            // Single bar: use average of all bins
            var sum: Float = 0
            vDSP_sve(allMagnitudes, 1, &sum, vDSP_Length(fftBins))
            magnitudes[0] = sum / Float(fftBins)
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
    
    // MARK: - Private Methods
    
    private func setUpFFT() {
        fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            UInt(bufferSize),
            vDSP_DFT_Direction.FORWARD
        )
    }
}

