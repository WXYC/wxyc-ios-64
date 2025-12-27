//
//  AVAudioStreamerAdapter.swift
//  Playback
//
//  Adapter to make AVAudioStreamer conform to AudioPlayerProtocol
//

import Foundation
import AVFoundation

// AVAudioStreamer is not available on watchOS
#if !os(watchOS)

/// Adapter that wraps AVAudioStreamer to conform to AudioPlayerProtocol
@MainActor
final class AVAudioStreamerAdapter: AudioPlayerProtocol {
    
    // MARK: - AudioPlayerProtocol
    
    var isPlaying: Bool {
        streamer.streamingState == .playing
    }
    
    var state: PlaybackState {
        streamer.state
    }
    
    var stateStream: AsyncStream<PlaybackState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        streamer.audioBufferStream
    }
    
    let eventStream: AsyncStream<AudioPlayerInternalEvent>
    
    // MARK: - Private Properties
    
    private let streamer: AVAudioStreamer
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation
    
    // MARK: - Initialization
    
    init(url: URL) {
        let config = AVAudioStreamerConfiguration(url: url)
        self.streamer = AVAudioStreamer(configuration: config)
        
        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation
    }
    
    // MARK: - AudioPlayerProtocol Methods
    
    func play() {
        Task {
            try? await streamer.play()
        }
    }
    
    func pause() {
        streamer.pause()
    }
    
    func resume() {
        Task {
            try? await streamer.play()
        }
    }
    
    func stop() {
        streamer.stop()
    }
}

#endif // !os(watchOS)
