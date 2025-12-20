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
    
    // MARK: - AudioPlayerProtocol
    
    var isPlaying: Bool = false
    var state: AudioPlayerPlaybackState = .stopped
    
    let stateStream: AsyncStream<AudioPlayerPlaybackState>
    let audioBufferStream: AsyncStream<AVAudioPCMBuffer>
    let eventStream: AsyncStream<AudioPlayerInternalEvent>
    
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStateChange: ((AudioPlayerPlaybackState, AudioPlayerPlaybackState) -> Void)?
    var onMetadata: (([String: String]) -> Void)?
    
    // MARK: - Private Properties
    
    private let url: URL
    
    init(url: URL = URL(string: "https://example.com/stream")!) {
        self.url = url
        self.stateStream = AsyncStream { $0.finish() }
        self.audioBufferStream = AsyncStream { $0.finish() }
        self.eventStream = AsyncStream { $0.finish() }
    }
    
    func play() {
        playCallCount += 1
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
