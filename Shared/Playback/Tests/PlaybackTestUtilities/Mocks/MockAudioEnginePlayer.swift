//
//  MockAudioEnginePlayer.swift
//  Playback
//
//  Mock audio engine player for testing MP3Streamer
//
//  Created by Jake Bromberg on 01/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
@preconcurrency import AVFoundation
import Analytics
@testable import MP3StreamerModule

#if !os(watchOS)

/// Mock audio engine player that simulates playback instantly without real audio
@MainActor
public final class MockAudioEnginePlayer: @preconcurrency AudioEnginePlayerProtocol {
    private let eventContinuation: AsyncStream<AudioPlayerEvent>.Continuation
    private let renderContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    public let analytics: MockAnalyticsService?

    public let eventStream: AsyncStream<AudioPlayerEvent>
    public let renderTapStream: AsyncStream<AVAudioPCMBuffer>

    public var volume: Float = 1.0
    public private(set) var isPlaying = false

    /// Track scheduled buffers
    public private(set) var scheduledBuffers: [AVAudioPCMBuffer] = []

    /// Track method calls
    public private(set) var playCallCount = 0
    public private(set) var pauseCallCount = 0
    public private(set) var stopCallCount = 0

    /// Whether play() should throw
    public var shouldThrowOnPlay = false
    public var playError: Error = AudioPlayerError.engineStartFailed

    /// If true, immediately call needsMoreBuffers after scheduling a buffer
    public var immediatelyRequestMoreBuffers = true

    public init(analytics: MockAnalyticsService? = nil) {
        self.analytics = analytics
        var eventCont: AsyncStream<AudioPlayerEvent>.Continuation!
        self.eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { eventCont = $0 }
        self.eventContinuation = eventCont

        var renderCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.renderTapStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { renderCont = $0 }
        self.renderContinuation = renderCont
    }

    public func play() throws {
        playCallCount += 1

        if shouldThrowOnPlay {
            throw playError
        }

        isPlaying = true
        eventContinuation.yield(.started)
    }

    public func pause() {
        pauseCallCount += 1
        isPlaying = false
        eventContinuation.yield(.paused)
    }

    public func stop() {
        stopCallCount += 1
        isPlaying = false
        scheduledBuffers.removeAll()
        eventContinuation.yield(.stopped)
    }

    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        scheduleBuffers([buffer])
    }

    public func scheduleBuffers(_ buffers: [AVAudioPCMBuffer]) {
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

    public func installRenderTap() {
        // No-op in mock - render stream is always "available"
    }

    public func removeRenderTap() {
        // No-op in mock
    }

    // MARK: - Test Helpers

    /// Manually yield an event for testing
    public func yield(_ event: AudioPlayerEvent) {
        eventContinuation.yield(event)
    }

    /// Simulate a stall
    public func simulateStall() {
        eventContinuation.yield(.stalled)
    }

    /// Simulate recovery from stall
    public func simulateRecovery() {
        eventContinuation.yield(.recoveredFromStall)
    }

    /// Finish the streams
    public func finish() {
        eventContinuation.finish()
        renderContinuation.finish()
    }
}

#endif
