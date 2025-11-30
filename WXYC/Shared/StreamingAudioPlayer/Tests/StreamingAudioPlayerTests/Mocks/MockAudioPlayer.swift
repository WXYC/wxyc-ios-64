//
//  MockAudioPlayer.swift
//  StreamingAudioPlayerTests
//
//  Mock implementation of AudioPlayerProtocol for testing
//

import Foundation
import AVFoundation
@testable import StreamingAudioPlayer

/// Mock audio player for testing
public final class MockAudioPlayer: AudioPlayerProtocol {
    
    // MARK: - State Tracking
    
    public var playCallCount = 0
    public var pauseCallCount = 0
    public var resumeCallCount = 0
    public var stopCallCount = 0
    public var lastPlayedURL: URL?
    
    // MARK: - AudioPlayerProtocol
    
    public var isPlaying: Bool = false
    public var state: AudioPlayerPlaybackState = .stopped
    public var currentURL: URL?
    
    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    public var onStateChange: ((AudioPlayerPlaybackState, AudioPlayerPlaybackState) -> Void)?
    public var onMetadata: (([String: String]) -> Void)?
    
    public init() {}
    
    public func play(url: URL) {
        playCallCount += 1
        lastPlayedURL = url
        currentURL = url
        let oldState = state
        state = .playing
        isPlaying = true
        onStateChange?(oldState, .playing)
    }
    
    public func pause() {
        pauseCallCount += 1
        let oldState = state
        state = .paused
        isPlaying = false
        onStateChange?(oldState, .paused)
    }
    
    public func resume() {
        resumeCallCount += 1
        let oldState = state
        state = .playing
        isPlaying = true
        onStateChange?(oldState, .playing)
    }
    
    public func stop() {
        stopCallCount += 1
        let oldState = state
        state = .stopped
        isPlaying = false
        currentURL = nil
        onStateChange?(oldState, .stopped)
    }
    
    // MARK: - Test Helpers
    
    public func reset() {
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
    public func simulateAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        onAudioBuffer?(buffer)
    }
    
    /// Simulate receiving metadata
    public func simulateMetadata(_ metadata: [String: String]) {
        onMetadata?(metadata)
    }
    
    /// Simulate a state change
    public func simulateStateChange(to newState: AudioPlayerPlaybackState) {
        let oldState = state
        state = newState
        isPlaying = (newState == .playing || newState == .buffering)
        onStateChange?(oldState, newState)
    }
}

