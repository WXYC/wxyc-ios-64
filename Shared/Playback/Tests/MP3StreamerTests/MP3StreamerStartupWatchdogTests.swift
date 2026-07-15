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
        // `connectionTimeout: 0` keeps the config's `startupTimeout` clamp
        // (`max(startupTimeout, connectionTimeout + 1)`) at its 1.0s floor, so the
        // watchdog fires quickly instead of at the default connectionTimeout + 1.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
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
        // watchdog fires after ~1s (the clamped startupTimeout floor) and
        // attemptReconnect() (first backoff wait is 0s) issues a second connect.
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 2 { break }
        }

        #expect(mockHTTP.connectCallCount >= 2,
                "Startup watchdog should escalate a starved buffering phase into a reconnect")
    }

    /// IOS-34: a reconnect that connects (HTTP 200 → `.buffering`) but starves
    /// before reaching `.playing` must itself be watched. Before #487 the watchdog
    /// armed only in `play()` and was never re-armed by `attemptReconnect()`, so the
    /// first escalation reconnect parked in `.buffering` with no live deadline and
    /// hung — `connectCallCount` plateaued at 2 (the initial connect + the single
    /// escalation reconnect). With the watchdog re-armed per reconnect, each starved
    /// reconnect re-escalates, driving further connects until the backoff exhausts.
    @Test("Re-arms the watchdog when a reconnect starves before playing")
    func reArmsWatchdogWhenReconnectStarves() async throws {
        // Tiny, clamped backoff waits so successive escalation reconnects fire almost
        // immediately. `connectionTimeout: 0` keeps the config's startupTimeout clamp
        // at its 1.0s floor so each starved buffering phase trips the watchdog fast.
        let backoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 10)
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // Every connect succeeds at the HTTP layer but no data ever arrives → each
        // attempt parks in buffering(0/5) and starves.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            backoffTimer: backoff
        )

        streamer.play()

        // Poll for a third connect: initial (1) + escalation reconnect (2) is all the
        // pre-#487 behavior produces. A third connect proves the reconnect's own
        // starvation was watched and re-escalated. Each escalation waits ~1s (the
        // clamped startupTimeout floor), so budget generously.
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 3 { break }
        }

        #expect(mockHTTP.connectCallCount >= 3,
                "The startup watchdog must be re-armed across reconnect connects so a starved reconnect re-escalates instead of hanging")
    }

    /// The re-armed watchdog must still disarm cleanly when a reconnect finally
    /// reaches `.playing`: after a starved first connect escalates, a subsequent
    /// reconnect that receives data must reach `.playing` and cancel the watchdog,
    /// issuing no further spurious reconnects.
    @Test(
        "A reconnect that reaches playing cancels the re-armed watchdog",
        .tags(.startupWatchdog, .slow),
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_SLOW"] == "1", "Slow test — excluded from CI")
    )
    func reconnectReachesPlayingCancelsWatchdog() async throws {
        let backoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 10)
        // `connectionTimeout: 0` keeps the startupTimeout clamp at its 1.0s floor.
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2,
            connectionTimeout: 0,
            startupTimeout: 0.3
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false

        // First connect starves; a later connect (the escalation reconnect) will be
        // fed real data so it can cross the buffer threshold into `.playing`.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            backoffTimer: backoff
        )

        streamer.play()

        // Wait for the starved initial buffering phase.
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if case .buffering = streamer.streamingState { break }
        }

        // Arm the recovery: the next connect (the watchdog's escalation reconnect)
        // now feeds real MP3 data and should reach `.playing`.
        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(50))
            if case .playing = streamer.streamingState { break }
        }

        guard case .playing = streamer.streamingState else {
            // Environment couldn't decode real MP3 — skip rather than fail.
            return
        }

        let connectsAtPlaying = mockHTTP.connectCallCount

        // Give the (now-cancelled) re-armed watchdog well past the ~1s clamped
        // startupTimeout to prove it does not fire another reconnect.
        try await Task.sleep(for: .milliseconds(1300))

        #expect(streamer.streamingState == .playing)
        #expect(mockHTTP.connectCallCount == connectsAtPlaying,
                "Reaching .playing on a reconnect must cancel the re-armed watchdog, not issue further reconnects")
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
        // `connectionTimeout: 0` keeps the startupTimeout clamp at its 1.0s floor.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
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

        // Wait well past the ~1s clamped startupTimeout — the watchdog must not fire a reconnect.
        try await Task.sleep(for: .milliseconds(1300))

        #expect(streamer.streamingState == .idle)
        #expect(mockHTTP.connectCallCount == 1,
                "A stopped streamer must not be reconnected by a stale startup watchdog")
    }

    /// Regression: if a mid-startup HTTP disconnect already scheduled a reconnect,
    /// the watchdog escalation must cancel that in-flight reconnect before starting
    /// its own. Otherwise it overwrites and leaks the pending `reconnectTask`, letting
    /// two connections race to completion and double-driving the reconnect machinery.
    ///
    /// `maximumAttempts: 1` bounds the scenario: the disconnect-triggered reconnect
    /// consumes the single backoff attempt, so the watchdog escalation exhausts the
    /// backoff immediately rather than re-arming into a fresh reconnect loop (#487).
    /// That makes the completion count deterministic: the initial connect completes,
    /// the hung reconnect is cancelled mid-flight (never completes), and no further
    /// connect is issued.
    @Test("Escalation cancels an in-flight reconnect instead of leaking it")
    func escalationCancelsInFlightReconnect() async throws {
        let backoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 1)
        // `connectionTimeout: 0` keeps the startupTimeout clamp at its 1.0s floor.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.2)
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

        // A mid-startup disconnect schedules a reconnect whose connect() hangs for
        // longer than the ~1s clamped startupTimeout, so it is still in flight when
        // the watchdog fires and escalates.
        mockHTTP.nextConnectDelay = .milliseconds(1500)
        mockHTTP.yield(.disconnected)

        // Let the watchdog fire (~1s) and escalate while that reconnect is pending,
        // then wait past the 1.5s hang so a *leaked* reconnect would have completed.
        try await Task.sleep(for: .milliseconds(2500))

        // The hung reconnect was issued (connectCallCount == 2) but cancelled mid-flight
        // by the escalation, so it never completed — only the initial connect did.
        #expect(mockHTTP.connectCallCount == 2,
                "The mid-startup disconnect must have issued exactly one reconnect")
        #expect(mockHTTP.connectCompletedCount == 1,
                "Watchdog escalation must cancel the in-flight reconnect, not leak it to completion")
    }
}

extension Tag {
    @Tag static var startupWatchdog: Self
}

#endif // !os(watchOS)
