//
//  StreamingAudioPlayer.swift
//  StreamingAudioPlayer
//
//  Low-level audio player that wraps AudioStreaming package
//

import Foundation
import AVFoundation
import AudioStreaming

/// Low-level audio player that wraps the AudioStreaming package
/// Handles basic playback control and state management
@Observable
public final class StreamingAudioPlayer: AudioPlayerProtocol {
    
    // MARK: - Public Properties
    
    public private(set) var isPlaying: Bool = false
    public private(set) var state: AudioPlayerPlaybackState = .stopped
    public private(set) var currentURL: URL?
    
    // MARK: - Callbacks
    
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    public var onStateChange: ((AudioPlayerPlaybackState, AudioPlayerPlaybackState) -> Void)?
    public var onMetadata: (([String: String]) -> Void)?
    
    // MARK: - Private Properties
    
    private let player: AudioPlayer
    
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
    
    private func setupFrameFilter() {
        let filter = FilterEntry(name: "audio-buffer-callback") { [weak self] buffer, _ in
            self?.onAudioBuffer?(buffer)
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
        
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(oldState, newState)
        }
    }
    
    private func mapPlayerState(_ playerState: AudioPlayerState) -> AudioPlayerPlaybackState {
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
    public func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId) {
        DispatchQueue.main.async { [weak self] in
            self?.updateState(.playing)
        }
    }
    
    public func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId) {
        // Buffering complete, state will update via state change callback
    }
    
    public func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let mappedState = self.mapPlayerState(newState)
            self.updateState(mappedState)
        }
    }
    
    public func audioPlayerDidFinishPlaying(player: AudioPlayer, entryId: AudioEntryId, stopReason: AudioPlayerStopReason, progress: Double, duration: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.updateState(.stopped)
        }
    }
    
    public func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError) {
        print("StreamingAudioPlayer error: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.updateState(.error)
        }
    }
    
    public func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {
        // Queue cancelled
    }
    
    public func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {
        DispatchQueue.main.async { [weak self] in
            self?.onMetadata?(metadata)
        }
    }
}

