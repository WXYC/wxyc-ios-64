import Foundation
@preconcurrency import AVFoundation
@testable import AVAudioStreamerModule

#if !os(watchOS)

/// Mock delegate for MP3StreamDecoder that captures decoded buffers and errors via AsyncStreams
final class MockMP3DecoderDelegate: MP3DecoderDelegate, Sendable {
    private let bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let errorContinuation: AsyncStream<Error>.Continuation

    let bufferStream: AsyncStream<AVAudioPCMBuffer>
    let errorStream: AsyncStream<Error>

    init() {
        var bufferCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        bufferStream = AsyncStream { bufferCont = $0 }
        bufferContinuation = bufferCont

        var errorCont: AsyncStream<Error>.Continuation!
        errorStream = AsyncStream { errorCont = $0 }
        errorContinuation = errorCont
    }

    deinit {
        bufferContinuation.finish()
        errorContinuation.finish()
    }

    func mp3Decoder(_ decoder: MP3StreamDecoder, didDecode buffer: AVAudioPCMBuffer) {
        bufferContinuation.yield(buffer)
    }

    func mp3Decoder(_ decoder: MP3StreamDecoder, didEncounterError error: Error) {
        errorContinuation.yield(error)
    }
}

#endif
