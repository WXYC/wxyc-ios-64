//
//  MockAudioPlayer.swift
//  StreamingAudioPlayerTests
//
//  Mock implementation of AudioPlayerProtocol for testing
//

import Foundation
import AVFoundation
@testable import Playback

/// Mock audio player for testing
final class MockAudioPlayer: AudioPlayerProtocol {
    
    // MARK: - State Tracking
    
    var playCallCount = 0
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopCallCount = 0
    
    var shouldAutoUpdateState = true
    
    // MARK: - AudioPlayerProtocol
    
    var isPlaying: Bool = false
    var state: AudioPlayerPlaybackState = .stopped
    
    let stateStream: AsyncStream<AudioPlayerPlaybackState>
    let audioBufferStream: AsyncStream<AVAudioPCMBuffer>
    let eventStream: AsyncStream<AudioPlayerInternalEvent>
    
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStateChange: ((AudioPlayerPlaybackState, AudioPlayerPlaybackState) -> Void)?
    var onMetadata: (([String: String]) -> Void)?
    var onStall: (() -> Void)?
    var onRecovery: (() -> Void)?
    
    // MARK: - Private Properties
    
    private let url: URL
    private var stateContinuation: AsyncStream<AudioPlayerPlaybackState>.Continuation?
    private var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation?
    
    init(url: URL = URL(string: "https://example.com/stream")!) {
        self.url = url
        
        var sC: AsyncStream<AudioPlayerPlaybackState>.Continuation!
        self.stateStream = AsyncStream { sC = $0 }
        self.stateContinuation = sC
        
        self.audioBufferStream = AsyncStream { $0.finish() }
        
        var eC: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { eC = $0 }
        self.eventContinuation = eC
    }
    
    func play() {
        playCallCount += 1
        
        if shouldAutoUpdateState {
            let oldState = state
            state = .playing
            isPlaying = true
            onStateChange?(oldState, .playing)
        }
    }
    
    func pause() {
        pauseCallCount += 1
        
        if shouldAutoUpdateState {
            let oldState = state
            state = .paused
            isPlaying = false
            onStateChange?(oldState, .paused)
        }
    }
    
    func resume() {
        resumeCallCount += 1
        
        if shouldAutoUpdateState {
            let oldState = state
            state = .playing
            isPlaying = true
            onStateChange?(oldState, .playing)
        }
    }
    
    func stop() {
        stopCallCount += 1
        
        if shouldAutoUpdateState {
            let oldState = state
            state = .stopped
            isPlaying = false
            onStateChange?(oldState, .stopped)
        }
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        playCallCount = 0
        pauseCallCount = 0
        resumeCallCount = 0
        stopCallCount = 0
        isPlaying = false
        state = .stopped
    }
    
    /// Simulate receiving an audio buffer
    
    /// Simulate receiving metadata
    
    /// Simulate a state change
    func simulateStateChange(to newState: AudioPlayerPlaybackState) {
        let oldState = state
        state = newState
        isPlaying = (newState == .playing || newState == .buffering)
        onStateChange?(oldState, newState)
    }
}

