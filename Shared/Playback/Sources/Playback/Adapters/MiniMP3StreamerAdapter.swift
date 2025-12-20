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
        guard let streamer = streamer else { return false }
        return streamer.state == .playing
    }
    
    var state: AudioPlayerPlaybackState {
        guard let streamer = streamer else { return .stopped }
        return mapState(streamer.state)
    }
    
    private(set) var currentURL: URL?
    
    var stateStream: AsyncStream<AudioPlayerPlaybackState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        streamer?.audioBufferStream ?? AsyncStream { $0.finish() }
    }
    
    let eventStream: AsyncStream<AudioPlayerInternalEvent>
    
    // MARK: - Private Properties
    
    private var streamer: MiniMP3Streamer?
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation
    
    // MARK: - Initialization
    
    init() {
        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation
    }
    
    // MARK: - AudioPlayerProtocol Methods
    
    func play(url: URL) {
        // Create new streamer with the URL if needed
        if currentURL != url || streamer == nil {
            streamer?.stop()
            let config = MiniMP3StreamerConfiguration(url: url)
            streamer = MiniMP3Streamer(configuration: config)
        }
        currentURL = url
        
        Task {
            try? await streamer?.play()
        }
    }
    
    func pause() {
        streamer?.pause()
    }
    
    func resume() {
        Task {
            try? await streamer?.play()
        }
    }
    
    func stop() {
        streamer?.stop()
        currentURL = nil
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
