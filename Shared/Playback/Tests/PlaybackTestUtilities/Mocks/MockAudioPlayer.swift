//
//  MockAudioPlayer.swift
//  PlaybackTestUtilities
//
//  Mock implementation of AudioPlayerProtocol for testing
//

import Foundation
import AVFoundation
@testable import Playback
@testable import PlaybackCore

/// Mock audio player for testing
public final class MockAudioPlayer: AudioPlayerProtocol {

    // MARK: - State Tracking

    public var playCallCount = 0
    public var stopCallCount = 0

    public var shouldAutoUpdateState = true

    // MARK: - AudioPlayerProtocol

    public var isPlaying: Bool = false
    public var state: PlayerState = .idle

    public let stateStream: AsyncStream<PlayerState>
    public let audioBufferStream: AsyncStream<AVAudioPCMBuffer>
    public let eventStream: AsyncStream<AudioPlayerInternalEvent>

    public var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    public var onStateChange: ((PlayerState, PlayerState) -> Void)?
    public var onMetadata: (([String: String]) -> Void)?
    public var onStall: (() -> Void)?
    public var onRecovery: (() -> Void)?

    // MARK: - Private Properties

    private let url: URL
    private var stateContinuation: AsyncStream<PlayerState>.Continuation?
    private var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation?

    public init(url: URL = URL(string: "https://example.com/stream")!) {
        self.url = url

        var sC: AsyncStream<PlayerState>.Continuation!
        self.stateStream = AsyncStream { sC = $0 }
        self.stateContinuation = sC

        self.audioBufferStream = AsyncStream { $0.finish() }

        var eC: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { eC = $0 }
        self.eventContinuation = eC
    }

    public func play() {
        playCallCount += 1

        if shouldAutoUpdateState {
            let oldState = state
            state = .playing
            isPlaying = true
            onStateChange?(oldState, .playing)
            stateContinuation?.yield(.playing)
        }
    }

    public func stop() {
        stopCallCount += 1

        if shouldAutoUpdateState {
            let oldState = state
            state = .idle
            isPlaying = false
            onStateChange?(oldState, .idle)
            stateContinuation?.yield(.idle)
        }
    }

    public func installRenderTap() {
        // No-op for mock
    }

    public func removeRenderTap() {
        // No-op for mock
    }

    // MARK: - Test Helpers

    public func reset() {
        playCallCount = 0
        stopCallCount = 0
        isPlaying = false
        state = .idle
    }

    /// Simulate a state change and notify observers via stateStream
    public func simulateStateChange(to newState: PlayerState) {
        let oldState = state
        state = newState
        isPlaying = (newState == .playing || newState == .loading)
        onStateChange?(oldState, newState)
        stateContinuation?.yield(newState)
    }

    /// Simulate a playback stall
    public func simulateStall() {
        onStall?()
        eventContinuation?.yield(.stall)
    }

    /// Simulate recovery from stall
    public func simulateRecovery() {
        onRecovery?()
        eventContinuation?.yield(.recovery)
    }
}

