//
//  StreamingAudioPlayer.swift
//  StreamingAudioPlayer
//
//  Low-level audio player that wraps the AudioStreaming package
//

#if !os(watchOS)
import Foundation
import AVFoundation

/// Low-level audio player that wraps the AudioStreaming package
/// Handles basic playback control and state management
@MainActor
@Observable
final class StreamingAudioPlayer: AudioPlayerProtocol {
    
    // MARK: - Public Properties
    
    private(set) var isPlaying: Bool = false
    private(set) var state: AudioPlayerPlaybackState = .stopped
    
    // MARK: - Streams
    
    let stateStream: AsyncStream<AudioPlayerPlaybackState>
    let audioBufferStream: AsyncStream<AVAudioPCMBuffer>
    let eventStream: AsyncStream<AudioPlayerInternalEvent>
    
    // MARK: - Private Properties
    
    private let url: URL
    @ObservationIgnored private let stateContinuation: AsyncStream<AudioPlayerPlaybackState>.Continuation
    @ObservationIgnored private let audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    @ObservationIgnored private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation
    
    @ObservationIgnored private let player: AudioPlayer
    
    // MARK: - Initialization
    
    init(url: URL) {
        self.url = url
        self.player = AudioPlayer()
        
        // Initialize Streams
        var stateContinuation: AsyncStream<AudioPlayerPlaybackState>.Continuation!
        self.stateStream = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.stateContinuation = stateContinuation
        
        // Audio Buffer Stream: bufferingNewest(1) to avoid blocking audio thread
        var audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.audioBufferStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            audioBufferContinuation = continuation
        }
        self.audioBufferContinuation = audioBufferContinuation
        
        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation
        
        setupFrameFilter()
        setupDelegate()
    }
    
    /// Internal initializer for testing with a custom player
    
    // MARK: - Setup
    
    /// Must be nonisolated so the closure passed to FilterEntry doesn't inherit MainActor isolation.
    /// This closure is called from a realtime audio thread and cannot have actor isolation requirements.
    nonisolated private func setupFrameFilter() {
        let continuation = audioBufferContinuation
        let filter = FilterEntry(name: "audio-buffer-callback") { buffer, _ in
            continuation.yield(buffer)
        }
        player.frameFiltering.add(entry: filter)
    }
    
    private func setupDelegate() {
        player.delegate = self
    }
    
    // MARK: - AudioPlayerProtocol
    
    func play() {
        player.play(url: url)
        updateState(.buffering)
    }
    
    func pause() {
        player.pause()
        updateState(.paused)
    }
    
    func resume() {
        player.resume()
        updateState(.playing)
    }
    
    func stop() {
        player.stop()
        updateState(.stopped)
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: AudioPlayerPlaybackState) {
        state = newState
        isPlaying = (newState == .playing || newState == .buffering)
        stateContinuation.yield(newState)
    }
    
    nonisolated private func mapPlayerState(_ playerState: AudioPlayerState) -> AudioPlayerPlaybackState {
        switch playerState {
        case .stalled, .reconnecting:
            return .buffering
        case .ready, .stopped:
            return .stopped
        case .running, .playing:
            return .playing
        case .paused:
            return .paused
        case .bufferring:
            return .buffering
        case .error:
            return .error
        case .disposed:
            return .stopped
        }
    }
}

// MARK: - AudioPlayerDelegate

extension StreamingAudioPlayer: AudioPlayerDelegate {
    nonisolated public func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId) {
        Task { @MainActor [weak self] in
            self?.updateState(.playing)
        }
    }
    
    nonisolated public func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId) {
        // Buffering complete, state will update via state change callback
    }
    
    nonisolated public func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        let mappedState = mapPlayerState(newState)
        Task { @MainActor [weak self] in
            self?.updateState(mappedState)
        }
    }
    
    nonisolated public func audioPlayerDidFinishPlaying(player: AudioPlayer, entryId: AudioEntryId, stopReason: AudioPlayerStopReason, progress: Double, duration: Double) {
        Task { @MainActor [weak self] in
            self?.updateState(.stopped)
        }
    }
    
    nonisolated public func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError) {
        print("StreamingAudioPlayer error: \(error)")
        Task { @MainActor [weak self] in
            self?.updateState(.error)
            self?.eventContinuation.yield(.error(error))
        }
    }
    
    nonisolated public func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {
        // Queue cancelled
    }
    
    nonisolated public func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {
        // Metadata removed
    }

    nonisolated public func audioPlayerDidStall(player: AudioPlayer) {
        Task { @MainActor [weak self] in
            self?.eventContinuation.yield(.stall)
        }
    }
    
    nonisolated public func audioPlayerDidRecoverFromStall(player: AudioPlayer) {
        Task { @MainActor [weak self] in
            self?.eventContinuation.yield(.recovery)
        }
    }
}
#endif
