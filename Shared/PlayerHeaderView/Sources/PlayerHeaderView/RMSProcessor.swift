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
final class RMSProcessor: @unchecked Sendable, SignalProcessor {
    let normalizerMutex: Mutex<any Normalizer>
    let barCount: Int
    
    /// - Parameters:
    ///   - barCount: Number of bars the frame is bucketed into
    ///   - normalizationMode: How to normalize RMS values for display
    init(barCount: Int = VisualizerConstants.barAmount, normalizationMode: NormalizationMode = .ema) {
        self.barCount = barCount
        self.normalizerMutex = Mutex(normalizationMode.createNormalizer(bandCount: barCount))
    }
    
    func process(data: UnsafeMutablePointer<Float>, frameLength: Int) -> [Float] {
        let samplesPerBar = frameLength / barCount
        var rmsValues = [Float](repeating: 0, count: barCount)
        
        for barIndex in 0..<barCount {
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
}
