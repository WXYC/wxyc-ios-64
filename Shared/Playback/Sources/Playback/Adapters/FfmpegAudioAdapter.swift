//
//  FfmpegAudioAdapter.swift
//  Playback
//
//  Adapter to make FfmpegAudio.StreamPlayer conform to AudioPlayerProtocol
//

// FfmpegAudio is only available on iOS (not watchOS due to arm64_32 exclusion)
#if canImport(FfmpegAudio) && os(iOS)
import Foundation
import AVFoundation
import FfmpegAudio

/// Adapter that wraps FfmpegAudio.StreamPlayer to conform to AudioPlayerProtocol
@MainActor
final class FfmpegAudioAdapter: AudioPlayerProtocol {
    
    // MARK: - AudioPlayerProtocol
    
    var isPlaying: Bool {
        player.state == .playing
    }
    
    var state: AudioPlayerPlaybackState {
        mapState(player.state)
    }
    
    var stateStream: AsyncStream<AudioPlayerPlaybackState> {
        AsyncStream { [weak self] continuation in
            continuation.finish()
        }
    }
    
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        audioBufferStreamContinuation.0
    }
    
    let eventStream: AsyncStream<AudioPlayerInternalEvent>
    
    // MARK: - Private Properties
    
    private let url: URL
    private let player = StreamPlayer()
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation
    private let audioBufferStreamContinuation: (AsyncStream<AVAudioPCMBuffer>, AsyncStream<AVAudioPCMBuffer>.Continuation)
    
    // MARK: - Initialization
    
    init(url: URL) {
        self.url = url
        
        // Setup event stream
        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation
        
        // Setup audio buffer stream
        var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        let bufferStream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .bufferingNewest(1)) { c in
            bufferContinuation = c
        }
        self.audioBufferStreamContinuation = (bufferStream, bufferContinuation)
        
        // Setup analysis handler to forward audio buffers
        player.analysisHandler = { [weak self] buffer, _ in
            self?.audioBufferStreamContinuation.1.yield(buffer)
        }
    }
    
    // MARK: - AudioPlayerProtocol Methods
    
    func play() {
        player.start(url: url)
    }
    
    func pause() {
        player.stop()
    }
    
    func resume() {
        player.start(url: url)
    }
    
    func stop() {
        player.stop()
    }
    
    // MARK: - Private Methods
    
    private func mapState(_ playerState: StreamPlayer.State) -> AudioPlayerPlaybackState {
        switch playerState {
        case .idle:
            return .stopped
        case .starting:
            return .buffering
        case .playing:
            return .playing
        case .stopping:
            return .stopped
        case .failed:
            return .error
        @unknown default:
            return .error
        }
    }
}

#endif // canImport(FfmpegAudio) && os(iOS)
