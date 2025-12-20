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
import AVAudioStreamer

/// Adapter that wraps AVAudioStreamer to conform to AudioPlayerProtocol
@MainActor
final class AVAudioStreamerAdapter: AudioPlayerProtocol {
    
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
    
    private var streamer: AVAudioStreamer?
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
            let config = AVAudioStreamerConfiguration(url: url)
            streamer = AVAudioStreamer(configuration: config)
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

#endif // !os(watchOS)
