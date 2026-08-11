//
//  SignalProcessor.swift
//  PlayerHeaderView
//
//  Shared state-management surface for the visualizer's audio processors.
//  FFTProcessor and RMSProcessor each protect their live Normalizer with a
//  Mutex; reset() and setNormalizationMode(_:) were byte-identical across
//  both, so this protocol extension owns them once and each processor
//  keeps only its specialized FFT/RMS-specific work.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Synchronization

/// An `AudioProcessor` whose normalization state is a mutex-protected
/// `Normalizer`. Conformers get `reset()` and `setNormalizationMode(_:)` for
/// free from the extension below.
protocol SignalProcessor: AudioProcessor {
    var normalizerMutex: Mutex<any Normalizer> { get }
}

extension SignalProcessor {
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
