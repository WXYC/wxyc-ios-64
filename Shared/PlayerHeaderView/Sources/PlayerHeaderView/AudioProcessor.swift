//
//  AudioProcessor.swift
//  PlayerHeaderView
//
//  Protocol for audio processing algorithms that produce visualization data
//
//  Created by Jake Bromberg on 12/02/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Accelerate

/// Protocol for audio processing algorithms that produce visualization data
protocol AudioProcessor: Sendable {
    /// Process audio data and return visualization values
    /// - Parameters:
    ///   - data: Pointer to audio sample data
    ///   - frameLength: Number of audio frames
    /// - Returns: Array of visualization values (one per bar)
    func process(data: UnsafeMutablePointer<Float>, frameLength: Int) -> [Float]
    
    /// Reset processor state
    func reset()
    
    /// Update normalization mode
    /// - Parameter mode: The normalization mode to use
    func setNormalizationMode(_ mode: NormalizationMode)
}
