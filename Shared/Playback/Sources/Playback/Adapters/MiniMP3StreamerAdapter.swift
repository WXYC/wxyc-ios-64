//
//  MiniMP3StreamerAdapter.swift
//  Playback
//
//  Adapter to make MiniMP3Streamer conform to AudioPlayerProtocol
//

import Foundation
import AVFoundation
import MiniMP3Streamer

/// Adapter that wraps MiniMP3Streamer to conform to AudioPlayerProtocol
@MainActor
final class MiniMP3StreamerAdapter: AudioPlayerProtocol {
    
    // MARK: - AudioPlayerProtocol
    
    var isPlaying: Bool {
        streamer.state == .playing
    }
    
    var state: AudioPlayerPlaybackState {
        mapState(streamer.state)
    }
    
    var stateStream: AsyncStream<AudioPlayerPlaybackState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        streamer.audioBufferStream
    }
    
    let eventStream: AsyncStream<AudioPlayerInternalEvent>
    
    // MARK: - Private Properties
    
    private let streamer: MiniMP3Streamer
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation
    
    // MARK: - Initialization
    
    init(url: URL) {
        let config = MiniMP3StreamerConfiguration(url: url)
        self.streamer = MiniMP3Streamer(configuration: config)
        
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
    
    // MARK: - Private Methods
    
    private func mapState(_ streamerState: StreamingAudioState) -> AudioPlayerPlaybackState {
        switch streamerState {
        case .idle:
            return .stopped
        case .connecting, .buffering:
            return .buffering
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .stalled, .reconnecting:
            return .buffering
        case .error:
            return .error
        }
    }
}
