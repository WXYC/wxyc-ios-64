//
//  MockAudioPlayer.swift
//  StreamingAudioPlayerTests
//
//  Mock implementation of AudioPlayerProtocol for testing
//

import Foundation
import AVFoundation
@testable import Playback
@testable import PlaybackCore

/// Mock audio player for testing
final class MockAudioPlayer: AudioPlayerProtocol {

    // MARK: - State Tracking

    var playCallCount = 0
    var stopCallCount = 0

    var shouldAutoUpdateState = true

    // MARK: - AudioPlayerProtocol

    var isPlaying: Bool = false
    var state: PlaybackState = .idle

    let stateStream: AsyncStream<PlaybackState>
    let audioBufferStream: AsyncStream<AVAudioPCMBuffer>
    let eventStream: AsyncStream<AudioPlayerInternalEvent>

    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStateChange: ((PlaybackState, PlaybackState) -> Void)?
    var onMetadata: (([String: String]) -> Void)?
    var onStall: (() -> Void)?
    var onRecovery: (() -> Void)?

    // MARK: - Private Properties

    private let url: URL
    private var stateContinuation: AsyncStream<PlaybackState>.Continuation?
    private var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation?

    init(url: URL = URL(string: "https://example.com/stream")!) {
        self.url = url

        var sC: AsyncStream<PlaybackState>.Continuation!
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
            stateContinuation?.yield(.playing)
        }
    }

    func stop() {
        stopCallCount += 1

        if shouldAutoUpdateState {
            let oldState = state
            state = .idle
            isPlaying = false
            onStateChange?(oldState, .idle)
            stateContinuation?.yield(.idle)
        }
    }

    // MARK: - Test Helpers

    func reset() {
        playCallCount = 0
        stopCallCount = 0
        isPlaying = false
        state = .idle
    }

    /// Simulate a state change and notify observers via stateStream
    func simulateStateChange(to newState: PlaybackState) {
        let oldState = state
        state = newState
        isPlaying = (newState == .playing || newState == .loading)
        onStateChange?(oldState, newState)
        stateContinuation?.yield(newState)
    }

    /// Simulate a playback stall
    func simulateStall() {
        onStall?()
        eventContinuation?.yield(.stall)
    }

    /// Simulate recovery from stall
    func simulateRecovery() {
        onRecovery?()
        eventContinuation?.yield(.recovery)
    }
}

