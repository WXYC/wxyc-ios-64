//
//  MockAudioPlayer.swift
//  PlayerHeaderViewTests
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
    
    // MARK: - AudioPlayerProtocol
    
    var isPlaying: Bool = false
    var state: AudioPlayerPlaybackState = .stopped
    var currentURL: URL?
    
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStateChange: ((AudioPlayerPlaybackState, AudioPlayerPlaybackState) -> Void)?
    var onMetadata: (([String: String]) -> Void)?
    
    init() {}
    
    func play(url: URL) {
        playCallCount += 1
        lastPlayedURL = url
        currentURL = url
        let oldState = state
        state = .playing
        isPlaying = true
        onStateChange?(oldState, .playing)
    }
    
    func pause() {
        pauseCallCount += 1
        let oldState = state
        state = .paused
        isPlaying = false
        onStateChange?(oldState, .paused)
    }
    
    func resume() {
        resumeCallCount += 1
        let oldState = state
        state = .playing
        isPlaying = true
        onStateChange?(oldState, .playing)
    }
    
    func stop() {
        stopCallCount += 1
        let oldState = state
        state = .stopped
        isPlaying = false
        currentURL = nil
        onStateChange?(oldState, .stopped)
    }
    
    // MARK: - Test Helpers
    
    /// Simulate receiving an audio buffer
    func simulateAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        onAudioBuffer?(buffer)
    }
    
    /// Simulate receiving metadata
    func simulateMetadata(_ metadata: [String: String]) {
        onMetadata?(metadata)
    }
    
    /// Simulate a state change
}
