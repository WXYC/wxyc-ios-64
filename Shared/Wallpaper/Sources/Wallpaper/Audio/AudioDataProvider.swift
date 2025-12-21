//
//  AudioDataProvider.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import Foundation
import Observation
import AVFoundation
import Accelerate

/// Observable audio analysis data for shader consumption.
@Observable
public final class AudioData: @unchecked Sendable {
    /// Overall audio amplitude (0.0 - 1.0)
    public var level: Float = 0.0

    /// Low frequency energy (0.0 - 1.0)
    public var bass: Float = 0.0

    /// Mid frequency energy (0.0 - 1.0)
    public var mid: Float = 0.0

    /// High frequency energy (0.0 - 1.0)
    public var high: Float = 0.0

    /// Beat intensity (0.0 - 1.0, pulses on beats)
    public var beat: Float = 0.0

    public init() {}
}

/// Analyzes PCM audio buffers and updates AudioData with frequency and amplitude information.
public actor AudioAnalyzer {
    private let audioData: AudioData
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int = 1024

    // For beat detection
    private var previousBassEnergy: Float = 0.0
    private var beatDecay: Float = 0.0

    // Smoothing factor for audio levels (0.0 = instant, 1.0 = no change)
    private let smoothingFactor: Float = 0.7

    public init(audioData: AudioData) {
        self.audioData = audioData
        self.fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    /// Process an audio buffer and update the AudioData.
    public func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Get mono signal (average of channels or just first channel)
        let channelCount = Int(buffer.format.channelCount)
        var monoSignal = [Float](repeating: 0, count: frameCount)

        if channelCount == 1 {
            monoSignal = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        } else {
            // Mix down to mono
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSignal[i] = sum / Float(channelCount)
            }
        }

        // Calculate RMS level
        var rms: Float = 0
        vDSP_rmsqv(monoSignal, 1, &rms, vDSP_Length(frameCount))
        let level = min(rms * 4.0, 1.0) // Scale and clamp

        // Perform FFT for frequency analysis
        let (bass, mid, high) = analyzeFrequencies(signal: monoSignal)

        // Beat detection based on bass transients
        let bassThreshold: Float = 0.15
        let bassIncrease = bass - previousBassEnergy
        var beatIntensity = beatDecay

        if bassIncrease > bassThreshold && bass > 0.3 {
            beatIntensity = 1.0
        }

        previousBassEnergy = bass
        beatDecay = max(0, beatIntensity - 0.05) // Decay the beat

        // Update audio data with smoothing
        let smooth = smoothingFactor
        let newLevel = audioData.level * smooth + level * (1.0 - smooth)
        let newBass = audioData.bass * smooth + bass * (1.0 - smooth)
        let newMid = audioData.mid * smooth + mid * (1.0 - smooth)
        let newHigh = audioData.high * smooth + high * (1.0 - smooth)
        let newBeat = beatIntensity

        // Update on main thread for observation
        Task { @MainActor in
            self.audioData.level = newLevel
            self.audioData.bass = newBass
            self.audioData.mid = newMid
            self.audioData.high = newHigh
            self.audioData.beat = newBeat
        }
    }

    private func analyzeFrequencies(signal: [Float]) -> (bass: Float, mid: Float, high: Float) {
        guard let fftSetup = fftSetup else {
            return (0, 0, 0)
        }

        let n = min(signal.count, fftSize)
        guard n > 0 else { return (0, 0, 0) }

        // Prepare input (pad with zeros if needed)
        var realInput = [Float](repeating: 0, count: fftSize)
        var imagInput = [Float](repeating: 0, count: fftSize)
        for i in 0..<n {
            realInput[i] = signal[i]
        }

        // Apply Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(realInput, 1, window, 1, &realInput, 1, vDSP_Length(fftSize))

        // Perform FFT
        var realOutput = [Float](repeating: 0, count: fftSize)
        var imagOutput = [Float](repeating: 0, count: fftSize)

        vDSP_DFT_Execute(fftSetup, realInput, imagInput, &realOutput, &imagOutput)

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        for i in 0..<(fftSize / 2) {
            magnitudes[i] = sqrt(realOutput[i] * realOutput[i] + imagOutput[i] * imagOutput[i])
        }

        // Frequency bands (assuming 44100 Hz sample rate)
        // Bass: 0-200 Hz, Mid: 200-2000 Hz, High: 2000-20000 Hz
        let binWidth = 44100.0 / Float(fftSize)
        let bassEnd = Int(200.0 / binWidth)
        let midEnd = Int(2000.0 / binWidth)

        var bassEnergy: Float = 0
        var midEnergy: Float = 0
        var highEnergy: Float = 0

        // Sum energies in each band
        for i in 0..<min(bassEnd, magnitudes.count) {
            bassEnergy += magnitudes[i]
        }
        for i in bassEnd..<min(midEnd, magnitudes.count) {
            midEnergy += magnitudes[i]
        }
        for i in midEnd..<magnitudes.count {
            highEnergy += magnitudes[i]
        }

        // Normalize
        let bassCount = Float(max(1, bassEnd))
        let midCount = Float(max(1, midEnd - bassEnd))
        let highCount = Float(max(1, magnitudes.count - midEnd))

        bassEnergy = min((bassEnergy / bassCount) / 50.0, 1.0)
        midEnergy = min((midEnergy / midCount) / 30.0, 1.0)
        highEnergy = min((highEnergy / highCount) / 20.0, 1.0)

        return (bassEnergy, midEnergy, highEnergy)
    }
}

/// Provider that connects to an audio buffer stream and updates AudioData.
public final class AudioDataProvider: @unchecked Sendable {
    public let audioData: AudioData
    private let analyzer: AudioAnalyzer
    private var processingTask: Task<Void, Never>?

    public init() {
        self.audioData = AudioData()
        self.analyzer = AudioAnalyzer(audioData: audioData)
    }

    /// Start processing audio from the given buffer stream.
    public func startProcessing(stream: AsyncStream<AVAudioPCMBuffer>) {
        stopProcessing()

        processingTask = Task { [analyzer] in
            for await buffer in stream {
                guard !Task.isCancelled else { break }
                await analyzer.process(buffer: buffer)
            }
        }
    }

    /// Stop processing audio.
    public func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }
}
