import Foundation
@preconcurrency import AVFoundation

#if !os(watchOS)

/// Factory for creating test audio formats and buffers
enum TestAudioBufferFactory {
    /// Standard format used by AudioEnginePlayer: 44.1kHz stereo float32
    static func makeStandardFormat() -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        )!
    }

    /// Creates a silent PCM buffer with the specified frame count
    static func makeSilentBuffer(frameCount: AVAudioFrameCount = 4096) -> AVAudioPCMBuffer {
        let format = makeStandardFormat()
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        // Buffer is already zeroed (silent) on creation
        return buffer
    }

    /// Creates a PCM buffer with a simple test tone (440Hz sine wave)
    static func makeTestToneBuffer(frameCount: AVAudioFrameCount = 4096, frequency: Float = 440.0) -> AVAudioPCMBuffer {
        let format = makeStandardFormat()
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let sampleRate = Float(format.sampleRate)
        guard let channelData = buffer.floatChannelData else { return buffer }

        for frame in 0..<Int(frameCount) {
            let sample = sin(2.0 * .pi * frequency * Float(frame) / sampleRate)
            // Write to both channels
            channelData[0][frame] = sample
            channelData[1][frame] = sample
        }

        return buffer
    }

    /// Loads the MP3 test fixture data from the test bundle
    static func loadMP3TestData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "Washing Machine (tweaked)", withExtension: "mp3") else {
            throw TestAudioError.fixtureNotFound
        }
        return try Data(contentsOf: url)
    }
}

enum TestAudioError: Error {
    case fixtureNotFound
}

#endif
