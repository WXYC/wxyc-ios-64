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
    var lastPlayedURL: URL?
    
    var shouldAutoUpdateState = true
    
    // MARK: - AudioPlayerProtocol
    
    var isPlaying: Bool = false
    var state: AudioPlayerPlaybackState = .stopped
    var currentURL: URL?
    
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStateChange: ((AudioPlayerPlaybackState, AudioPlayerPlaybackState) -> Void)?
    var onMetadata: (([String: String]) -> Void)?
    var onStall: (() -> Void)?
    var onRecovery: (() -> Void)?
    
    init() {}
    
    func play(url: URL) {
        playCallCount += 1
        lastPlayedURL = url
        currentURL = url
        
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
            currentURL = nil
            onStateChange?(oldState, .stopped)
        }
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        playCallCount = 0
        pauseCallCount = 0
        resumeCallCount = 0
        stopCallCount = 0
        lastPlayedURL = nil
        isPlaying = false
        state = .stopped
        currentURL = nil
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



