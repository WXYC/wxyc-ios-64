//
//  RadioPlayerAdapter.swift
//  Playback
//
//  Adapter to make RadioPlayer conform to AudioPlayerProtocol
//

import Foundation
import AVFoundation

/// Adapter that wraps RadioPlayer to conform to AudioPlayerProtocol
@MainActor
final class RadioPlayerAdapter: AudioPlayerProtocol {
    
    // MARK: - AudioPlayerProtocol
    
    var isPlaying: Bool {
        radioPlayer.isPlaying
    }
    
    private(set) var state: AudioPlayerPlaybackState = .stopped
    private(set) var currentURL: URL?
    
    let stateStream: AsyncStream<AudioPlayerPlaybackState>
    let audioBufferStream: AsyncStream<AVAudioPCMBuffer>
    let eventStream: AsyncStream<AudioPlayerInternalEvent>
    
    // MARK: - Private Properties
    
    private let radioPlayer: RadioPlayer
    private let stateContinuation: AsyncStream<AudioPlayerPlaybackState>.Continuation
    private let audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation
    
    // MARK: - Initialization
    
    init() {
        self.radioPlayer = RadioPlayer()
        
        // Initialize streams
        var stateContinuation: AsyncStream<AudioPlayerPlaybackState>.Continuation!
        self.stateStream = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.stateContinuation = stateContinuation
        
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
    }
    
    // MARK: - AudioPlayerProtocol Methods
    
    func play(url: URL) {
        currentURL = url
        radioPlayer.play()
        updateState(.playing)
    }
    
    func pause() {
        radioPlayer.pause()
        updateState(.paused)
    }
    
    func resume() {
        radioPlayer.play()
        updateState(.playing)
    }
    
    func stop() {
        radioPlayer.pause()
        currentURL = nil
        updateState(.stopped)
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: AudioPlayerPlaybackState) {
        state = newState
        stateContinuation.yield(newState)
    }
}
