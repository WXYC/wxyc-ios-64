//
//  SignalProcessorTests.swift
//  PlayerHeaderView
//
//  Coverage for the state-management surface FFTProcessor and RMSProcessor
//  share — reset() and setNormalizationMode(_:) — hoisted onto a common
//  SignalProcessor protocol extension so the two byte-identical
//  implementations collapse to one (WXYC/wxyc-ios-64#326).
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import PlayerHeaderView

@Suite("SignalProcessor shared state management")
struct SignalProcessorTests {
    private static let sampleRate: Float = 44_100
    private static let frameLength = 4_096

    /// A synthetic 1kHz tone, scaled by `amplitude`. FFT/RMS magnitude both
    /// scale linearly (RMS exactly, FFT magnitude by linearity of the DFT)
    /// with the amplitude of a fixed waveform, which the reset/mode tests
    /// below lean on.
    private static func tone(amplitude: Float) -> [Float] {
        let angularStep: Float = 2 * .pi * 1_000 / sampleRate
        return (0..<frameLength).map { i in
            let angle: Float = angularStep * Float(i)
            return amplitude * sin(angle)
        }
    }

    private static func process(_ processor: any AudioProcessor, amplitude: Float) throws -> [Float] {
        var buffer = tone(amplitude: amplitude)
        return try buffer.withUnsafeMutableBufferPointer { pointer in
            let base = try #require(pointer.baseAddress)
            return processor.process(data: base, frameLength: frameLength)
        }
    }

    private static func makeFFTProcessor(mode: NormalizationMode) -> FFTProcessor {
        FFTProcessor(normalizationMode: mode, frequencyWeightingExponent: 0)
    }

    private static func makeRMSProcessor(mode: NormalizationMode) -> RMSProcessor {
        RMSProcessor(normalizationMode: mode)
    }

    // MARK: - reset()

    // A fresh `.ema` normalizer's first call always sets its running peak to
    // that call's own max, so the output max lands exactly at
    // `magnitudeLimit`. If `reset()` actually clears the running peak left
    // by a prior loud call, the next call reproduces that fresh-instance
    // behavior; if `reset()` were a no-op, the lingering peak would suppress
    // it well below `magnitudeLimit`.
    @Test("reset() clears the EMA running peak — FFTProcessor")
    func fftResetClearsRunningPeak() throws {
        let processor = Self.makeFFTProcessor(mode: .ema)
        _ = try Self.process(processor, amplitude: 1.0)
        processor.reset()
        let output = try Self.process(processor, amplitude: 0.2)
        #expect(abs((output.max() ?? 0) - VisualizerConstants.magnitudeLimit) < 0.01)
    }

    @Test("reset() clears the EMA running peak — RMSProcessor")
    func rmsResetClearsRunningPeak() throws {
        let processor = Self.makeRMSProcessor(mode: .ema)
        _ = try Self.process(processor, amplitude: 1.0)
        processor.reset()
        let output = try Self.process(processor, amplitude: 0.2)
        #expect(abs((output.max() ?? 0) - VisualizerConstants.magnitudeLimit) < 0.01)
    }

    @Test("without reset(), a prior loud call suppresses the next quiet call — FFTProcessor")
    func fftWithoutResetPeakLingers() throws {
        let processor = Self.makeFFTProcessor(mode: .ema)
        _ = try Self.process(processor, amplitude: 1.0)
        let output = try Self.process(processor, amplitude: 0.2)
        #expect((output.max() ?? 0) < VisualizerConstants.magnitudeLimit - 0.01)
    }

    @Test("without reset(), a prior loud call suppresses the next quiet call — RMSProcessor")
    func rmsWithoutResetPeakLingers() throws {
        let processor = Self.makeRMSProcessor(mode: .ema)
        _ = try Self.process(processor, amplitude: 1.0)
        let output = try Self.process(processor, amplitude: 0.2)
        #expect((output.max() ?? 0) < VisualizerConstants.magnitudeLimit - 0.01)
    }

    // MARK: - setNormalizationMode(_:)

    // `.none` passes raw magnitudes through unscaled; switching to `.ema`
    // hands the processor a fresh normalizer whose first call always
    // normalizes its own peak to exactly `magnitudeLimit`. Observing both
    // proves the mode switch actually swapped the live normalizer rather
    // than leaving the old one in place.
    @Test("setNormalizationMode swaps the live normalizer — FFTProcessor")
    func fftSetNormalizationModeSwaps() throws {
        let processor = Self.makeFFTProcessor(mode: .none)
        let rawOutput = try Self.process(processor, amplitude: 0.3)
        processor.setNormalizationMode(.ema)
        let normalizedOutput = try Self.process(processor, amplitude: 0.3)
        #expect(rawOutput != normalizedOutput)
        #expect(abs((normalizedOutput.max() ?? 0) - VisualizerConstants.magnitudeLimit) < 0.01)
    }

    @Test("setNormalizationMode swaps the live normalizer — RMSProcessor")
    func rmsSetNormalizationModeSwaps() throws {
        let processor = Self.makeRMSProcessor(mode: .none)
        let rawOutput = try Self.process(processor, amplitude: 0.3)
        processor.setNormalizationMode(.ema)
        let normalizedOutput = try Self.process(processor, amplitude: 0.3)
        #expect(rawOutput != normalizedOutput)
        #expect(abs((normalizedOutput.max() ?? 0) - VisualizerConstants.magnitudeLimit) < 0.01)
    }
}
