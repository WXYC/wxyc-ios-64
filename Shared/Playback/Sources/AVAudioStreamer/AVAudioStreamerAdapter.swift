//
//  AVAudioStreamerAdapter.swift
//  Playback
//
//  Adapter to make AVAudioStreamer conform to AudioPlayerProtocol
//

import Foundation
import AVFoundation
import PlaybackCore

// AVAudioStreamer is not available on watchOS
#if !os(watchOS)

/// Adapter that wraps AVAudioStreamer to conform to AudioPlayerProtocol
@MainActor
public final class AVAudioStreamerAdapter: AudioPlayerProtocol {

    // MARK: - AudioPlayerProtocol

    public var isPlaying: Bool {
        streamer.streamingState == .playing
    }

    public var state: PlaybackState {
        streamer.state
    }

    public var stateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        streamer.audioBufferStream
    }

    public let eventStream: AsyncStream<AudioPlayerInternalEvent>

    // MARK: - Private Properties

    private let streamer: AVAudioStreamer
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation

    // MARK: - Initialization

    public init(url: URL) {
        let config = AVAudioStreamerConfiguration(url: url)
        self.streamer = AVAudioStreamer(configuration: config)

        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation
    }

    // MARK: - AudioPlayerProtocol Methods

    public func play() {
        Task {
            try? await streamer.play()
        }
    }

    public func stop() {
        streamer.stop()
    }
}

#endif // !os(watchOS)
