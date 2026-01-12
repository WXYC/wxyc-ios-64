//
//  MockAudioEnginePlayer.swift
//  PlaybackTests
//
//  Mock audio engine player for testing MP3Streamer
//

import Foundation
@preconcurrency import AVFoundation
@testable import MP3StreamerModule

#if !os(watchOS)

/// Mock audio engine player that simulates playback instantly without real audio
final class MockAudioEnginePlayer: AudioEnginePlayerProtocol, @unchecked Sendable {
    private let eventContinuation: AsyncStream<AudioPlayerEvent>.Continuation
    private let renderContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    let eventStream: AsyncStream<AudioPlayerEvent>
    let renderTapStream: AsyncStream<AVAudioPCMBuffer>

    var volume: Float = 1.0
    private(set) var isPlaying = false

    /// Track scheduled buffers
    private(set) var scheduledBuffers: [AVAudioPCMBuffer] = []

    /// Track method calls
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var stopCallCount = 0

    /// Whether play() should throw
    var shouldThrowOnPlay = false
    var playError: Error = AudioPlayerError.engineStartFailed

    /// If true, immediately call needsMoreBuffers after scheduling a buffer
    var immediatelyRequestMoreBuffers = true

    init() {
        var eventCont: AsyncStream<AudioPlayerEvent>.Continuation!
        self.eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { eventCont = $0 }
        self.eventContinuation = eventCont

        var renderCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.renderTapStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { renderCont = $0 }
        self.renderContinuation = renderCont
    }

    func play() throws {
        playCallCount += 1

        if shouldThrowOnPlay {
            throw playError
        }

        isPlaying = true
        eventContinuation.yield(.started)
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
        eventContinuation.yield(.paused)
    }

    func stop() {
        stopCallCount += 1
        isPlaying = false
        scheduledBuffers.removeAll()
        eventContinuation.yield(.stopped)
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        scheduleBuffers([buffer])
    }

    func scheduleBuffers(_ buffers: [AVAudioPCMBuffer]) {
        scheduledBuffers.append(contentsOf: buffers)

        // Simulate instant "playback" - yield last buffer to render stream
        if let lastBuffer = buffers.last {
            renderContinuation.yield(lastBuffer)
        }

        // Immediately request more buffers to simulate fast playback
        if immediatelyRequestMoreBuffers && !buffers.isEmpty {
            eventContinuation.yield(.needsMoreBuffers)
        }
    }

    func installRenderTap() {
        // No-op in mock - render stream is always "available"
    }

    func removeRenderTap() {
        // No-op in mock
    }

    // MARK: - Test Helpers

    /// Manually yield an event for testing
    func yield(_ event: AudioPlayerEvent) {
        eventContinuation.yield(event)
    }

    /// Simulate a stall
    func simulateStall() {
        eventContinuation.yield(.stalled)
    }

    /// Simulate recovery from stall
    func simulateRecovery() {
        eventContinuation.yield(.recoveredFromStall)
    }

    /// Finish the streams
    func finish() {
        eventContinuation.finish()
        renderContinuation.finish()
    }
}

#endif
