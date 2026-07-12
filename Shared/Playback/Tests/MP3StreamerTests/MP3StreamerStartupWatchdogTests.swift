//
//  MP3StreamerStartupWatchdogTests.swift
//  Playback
//
//  Tests for the startup watchdog that escalates when playback connects but
//  never reaches the .playing state (Sentry IOS-31: "Playback not starting").
//
//  Created by Jake Bromberg on 07/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
@testable import MP3StreamerModule
import Core

#if !os(watchOS)

@Suite("MP3Streamer Startup Watchdog")
@MainActor
struct MP3StreamerStartupWatchdogTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    /// The core regression (IOS-31): the stream connects (HTTP 200) but the byte
    /// stream starves before crossing the buffer threshold, so it parks in
    /// `.buffering` forever. The watchdog must escalate and attempt a fresh
    /// reconnect instead of hanging.
    @Test("Escalates and reconnects when buffering starves before playing")
    func escalatesWhenBufferingStarves() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // Connect succeeds, but no data ever arrives → stuck in buffering(0/5).
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()

        // Without the watchdog, connectCallCount stays 1 forever. With it, the
        // watchdog fires after ~0.1s and attemptReconnect() (first backoff wait
        // is 0s) issues a second connect.
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 2 { break }
        }

        #expect(mockHTTP.connectCallCount >= 2,
                "Startup watchdog should escalate a starved buffering phase into a reconnect")
    }

    /// The watchdog must be a no-op on a healthy startup: once `.playing` is
    /// reached it is cancelled and never issues a spurious reconnect.
    @Test(
        "Does not fire once playback has started",
        .tags(.startupWatchdog, .slow),
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_SLOW"] == "1", "Slow test — excluded from CI")
    )
    func doesNotFireOncePlaying() async throws {
        // startupTimeout comfortably exceeds the decode-to-playing time so a
        // healthy start never trips it; cancellation on `.playing` is what we assert.
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2,
            startupTimeout: 5.0
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false

        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()

        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if case .playing = streamer.streamingState { break }
        }

        guard case .playing = streamer.streamingState else {
            // Environment couldn't decode real MP3 — skip rather than fail.
            return
        }

        // Give the (cancelled) watchdog a moment; it must not fire a reconnect.
        try await Task.sleep(for: .milliseconds(200))

        #expect(streamer.streamingState == .playing)
        #expect(mockHTTP.connectCallCount == 1,
                "Watchdog must be cancelled on reaching .playing, not issue a reconnect")
    }

    /// Stopping before the deadline must cancel the watchdog so it can't fire a
    /// reconnect against an intentionally-stopped streamer.
    @Test("Is cancelled by stop() before it can fire")
    func cancelledByStop() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()

        // Wait until the watchdog is provably armed before stopping. Arming happens
        // inside play()'s deferred Task immediately before connect(), so a completed
        // connect (connectCallCount == 1) guarantees the watchdog is live. Stopping on
        // a fixed short sleep could race ahead of the deferred Task and cancel nothing,
        // letting this test pass vacuously.
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 1 { break }
        }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the watchdog must be armed before stop()")

        streamer.stop()

        // Wait well past the startupTimeout — the watchdog must not fire a reconnect.
        try await Task.sleep(for: .milliseconds(200))

        #expect(streamer.streamingState == .idle)
        #expect(mockHTTP.connectCallCount == 1,
                "A stopped streamer must not be reconnected by a stale startup watchdog")
    }

    /// Regression: if a mid-startup HTTP disconnect already scheduled a reconnect,
    /// the watchdog escalation must cancel that in-flight reconnect before starting
    /// its own. Otherwise it overwrites and leaks the pending `reconnectTask`, letting
    /// two connections race to completion and double-driving the reconnect machinery.
    @Test("Escalation cancels an in-flight reconnect instead of leaking it")
    func escalationCancelsInFlightReconnect() async throws {
        // Tiny, clamped backoff waits so the escalation's own reconnect is effectively
        // immediate (the random addition is clamped to maximumWaitTime).
        let backoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 10)
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, startupTimeout: 0.2)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            backoffTimer: backoff
        )

        streamer.play()

        // Reach buffering — the initial connect completes immediately.
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if case .buffering = streamer.streamingState { break }
        }
        #expect(mockHTTP.connectCompletedCount == 1, "Precondition: the initial connect completed")

        // A mid-startup disconnect schedules a reconnect whose connect() then hangs,
        // so it is still in flight when the watchdog fires ~0.2s in.
        mockHTTP.nextConnectDelay = .milliseconds(400)
        mockHTTP.yield(.disconnected)

        // Let the watchdog fire and escalate while that reconnect is pending, then wait
        // past the 0.4s hang so a *leaked* reconnect would have completed as a 3rd.
        try await Task.sleep(for: .milliseconds(700))

        // Only the initial connect and the escalation's fresh reconnect should complete.
        // The superseded, hung reconnect must have been cancelled, not leaked.
        #expect(mockHTTP.connectCompletedCount == 2,
                "Watchdog escalation must cancel the in-flight reconnect, not leak it to completion")
    }
}

extension Tag {
    @Tag static var startupWatchdog: Self
}

#endif // !os(watchOS)
