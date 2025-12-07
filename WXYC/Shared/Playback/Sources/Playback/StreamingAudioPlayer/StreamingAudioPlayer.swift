//
//  StreamingAudioPlayer.swift
//  StreamingAudioPlayer
//
//  Low-level audio player that wraps the AudioStreaming package
//

#if !os(watchOS)
import Foundation
import AVFoundation

/// Holds audio buffer callback in a non-actor-isolated way for realtime audio thread access
private final class AudioBufferCallbackHolder: @unchecked Sendable {
    var callback: ((AVAudioPCMBuffer) -> Void)?
}

/// Low-level audio player that wraps the AudioStreaming package
/// Handles basic playback control and state management
@MainActor
@Observable
public final class StreamingAudioPlayer: AudioPlayerProtocol {
    
    // MARK: - Public Properties
    
    public private(set) var isPlaying: Bool = false
    public private(set) var state: AudioPlayerPlaybackState = .stopped
    public private(set) var currentURL: URL?
    
    // MARK: - Callbacks
    
    /// Callback for audio buffer data. Called from realtime audio thread.
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { audioBufferCallbackHolder.callback }
        set { audioBufferCallbackHolder.callback = newValue }
    }
    public var onStateChange: ((AudioPlayerPlaybackState, AudioPlayerPlaybackState) -> Void)?
    public var onMetadata: (([String: String]) -> Void)?
    
    // MARK: - Private Properties
    
    /// Must be nonisolated so setupFrameFilter can access it without inheriting MainActor isolation
    @ObservationIgnored nonisolated private let audioBufferCallbackHolder = AudioBufferCallbackHolder()
    @ObservationIgnored private let player: AudioPlayer
    
    // MARK: - Initialization
    
    public init() {
        self.player = AudioPlayer()
        setupFrameFilter()
        setupDelegate()
    }
    
    /// Internal initializer for testing with a custom player
    internal init(player: AudioPlayer) {
        self.player = player
        setupFrameFilter()
        setupDelegate()
    }
    
    // MARK: - Setup
    
    /// Must be nonisolated so the closure passed to FilterEntry doesn't inherit MainActor isolation.
    /// This closure is called from a realtime audio thread and cannot have actor isolation requirements.
    nonisolated private func setupFrameFilter() {
        let holder = audioBufferCallbackHolder
        let filter = FilterEntry(name: "audio-buffer-callback") { buffer, _ in
            holder.callback?(buffer)
        }
        player.frameFiltering.add(entry: filter)
    }
    
    private func setupDelegate() {
        player.delegate = self
    }
    
    // MARK: - AudioPlayerProtocol
    
    public func play(url: URL) {
        currentURL = url
        player.play(url: url)
        updateState(.buffering)
    }
    
    public func pause() {
        player.pause()
        updateState(.paused)
    }
    
    public func resume() {
        player.resume()
        updateState(.playing)
    }
    
    public func stop() {
        player.stop()
        currentURL = nil
        updateState(.stopped)
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: AudioPlayerPlaybackState) {
        let oldState = state
        state = newState
        isPlaying = (newState == .playing || newState == .buffering)
        onStateChange?(oldState, newState)
    }
    
    nonisolated private func mapPlayerState(_ playerState: AudioPlayerState) -> AudioPlayerPlaybackState {
        switch playerState {
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
        }
    }
    
    nonisolated public func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {
        // Queue cancelled
    }
    
    nonisolated public func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {
        Task { @MainActor [weak self] in
            self?.onMetadata?(metadata)
        }
    }
}
#endif
