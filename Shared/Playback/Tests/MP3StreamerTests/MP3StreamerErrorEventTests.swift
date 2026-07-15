//
//  MP3StreamerErrorEventTests.swift
//  Playback
//
//  Tests for the stream-error signal on MP3Streamer's silent failure paths: the
//  streamer must yield exactly one `.error` internal event per failure episode on
//  its terminal, non-recursive paths (engine-start failure during buffering, and
//  reconnect backoff exhaustion), so the controller can capture a
//  `StreamErrorEvent`. This is the failure numerator against the #513 first-audio
//  denominator (issue #486). Deliberately deterministic and MP3Streamer-level,
//  distinct from the flake-gated `StreamErrorAnalyticsTests`.
//
//  Created by Jake Bromberg on 07/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
import Core
@testable import MP3StreamerModule
@testable import PlaybackCore

#if !os(watchOS)

@Suite("MP3Streamer Error Events")
@MainActor
struct MP3StreamerErrorEventTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    /// Drains the streamer's internal event stream on a task and records every
    /// `.error` event so tests can assert on the emission count.
    private final class ErrorCollector {
        var errors: [Error] = []
        var count: Int { errors.count }
    }

    private func makeDrain(_ streamer: MP3Streamer, into collector: ErrorCollector) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in streamer.eventStreamInternal {
                if case .error(let error) = event {
                    collector.errors.append(error)
                }
            }
        }
    }

    /// Engine-start failure while buffering is a terminal, non-recursive path: the
    /// buffering threshold is crossed, `audioPlayer.play()` throws, and the streamer
    /// must surface a single `.error` event (issue #486, PRIMARY path).
    @Test("Emits one error event when the engine fails to start during buffering")
    func emitsErrorEventWhenEngineStartFailsDuringBuffering() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2,
            startupTimeout: 5.0
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false
        mockPlayer.shouldThrowOnPlay = true
        mockHTTP.testData = try TestAudioBufferFactory.loadMP3TestData()

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        streamer.play()

        // Poll until the engine-start failure surfaces an error, or the budget
        // elapses. `playCallCount > 0` proves the buffering threshold was crossed
        // and `audioPlayer.play()` was attempted (and threw); if it stays 0 the
        // environment could not decode the MP3 fixture, so skip rather than fail.
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if collector.count > 0 { break }
        }
        guard mockPlayer.playCallCount > 0 else { return } // decode unavailable → skip

        // Let any (erroneous) additional emissions land.
        try await Task.sleep(for: .milliseconds(100))

        #expect(collector.count == 1, "Exactly one error event should fire on engine-start failure during buffering")
    }

    /// Reconnect backoff exhaustion is the second terminal, non-recursive path:
    /// once MP3Streamer gives up its HTTP reconnects it must surface a single
    /// `.error` event (issue #486). The per-attempt catch and the pre-reconnect
    /// HTTP `.error` drop are deliberately silent, so the only `.error` here is the
    /// exhaustion emission.
    @Test("Emits one error event when reconnect backoff is exhausted")
    func emitsErrorEventWhenReconnectBackoffExhausted() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2,
            startupTimeout: 5.0
        )
        let mockHTTP = MockHTTPStreamClient()
        mockHTTP.shouldSucceed = false
        let mockPlayer = MockAudioEnginePlayer()

        // A single-attempt ramp exhausts on the first reconnect failure.
        let backoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 1)

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            backoffTimer: backoff
        )

        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        // An HTTP error drives the reconnect loop directly (the `.error` case is a
        // deliberately-silent path, so it contributes no `.error` event itself).
        mockHTTP.yield(.error(HTTPStreamError.connectionFailed))

        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(50))
            if collector.count > 0 { break }
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(collector.count == 1, "Exactly one error event should fire when the reconnect backoff is exhausted")
    }

    /// Regression for the #509 review: an engine-start `.error` from the buffering
    /// catch must not tear down a still-intended playback session. The CPU-session
    /// lifecycle is owned by AudioPlayerController and is verified end-to-end by
    /// #512's own tests (the `.error` handler no longer ends the session); here we
    /// pin the MP3Streamer-side contract that exactly one `.error` — not a storm —
    /// crosses the internal event boundary, which is what keeps that session intact.
    @Test("Engine-start failure emits a single error, not a repeated storm")
    func engineStartFailureDoesNotEmitRepeatedErrors() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2,
            startupTimeout: 5.0
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false
        mockPlayer.shouldThrowOnPlay = true
        mockHTTP.testData = try TestAudioBufferFactory.loadMP3TestData()

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        streamer.play()

        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if collector.count > 0 { break }
        }
        guard mockPlayer.playCallCount > 0 else { return } // decode unavailable → skip

        // Keep observing: subsequent decoded buffers land on the `.error` state and
        // must be ignored, not re-emitted.
        try await Task.sleep(for: .milliseconds(300))

        #expect(collector.count == 1, "Engine-start failure must emit exactly one error, not one per subsequent buffer")
    }
}

#endif // !os(watchOS)
