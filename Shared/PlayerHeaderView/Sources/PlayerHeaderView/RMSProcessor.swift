//
//  RMSProcessor.swift
//  PlayerHeaderView
//
//  Root Mean Square processor for time domain visualization
//
//  Created by Jake Bromberg on 12/02/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Accelerate
import Synchronization

/// Root Mean Square processor for time domain visualization
/// Note: @unchecked Sendable because it's primarily accessed from the single-threaded audio processing context.
/// The normalizer property is protected with Mutex for thread-safe access when normalization mode changes from MainActor.
final class RMSProcessor: @unchecked Sendable, AudioProcessor {
    private let normalizerMutex: Mutex<any Normalizer>
    
    init(normalizationMode: NormalizationMode = .ema) {
        self.normalizerMutex = Mutex(normalizationMode.createNormalizer())
    }
    
    func process(data: UnsafeMutablePointer<Float>, frameLength: Int) -> [Float] {
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
        
        // Apply normalization (thread-safe access)
        normalizerMutex.withLock { normalizer in
            normalizer.normalize(&rmsValues, outputScale: VisualizerConstants.magnitudeLimit)
        }
        
        return rmsValues
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
}
