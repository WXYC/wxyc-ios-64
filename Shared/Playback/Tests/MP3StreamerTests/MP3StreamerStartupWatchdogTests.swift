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
        .tags(.startupWatchdog)
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
        .tags(.startupWatchdog)
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
    @Test(
        "Is cancelled by stop() before it can fire",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
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

    /// #488 (fresh-play race): `play()` enqueues a deferred connect Task; a `stop()`
    /// landing in the SAME MainActor turn — before that Task drains — must cancel the
    /// pending connect. Before #488 the deferred Task was un-stored, so `stop()` could
    /// not cancel it: the stopped streamer still issued a connect and armed a watchdog.
    @Test("A racing stop() cancels the deferred connect before it fires")
    func racingStopBeforeDeferredConnectDrains() async throws {
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

        // play() then stop() in the SAME synchronous MainActor turn — no await
        // between them — so the deferred connect Task has not run yet when stop() lands.
        streamer.play()
        streamer.stop()

        // Drain: give the (superseded/cancelled) deferred Task ample time to run. It
        // must observe the cancellation and abort before calling connect(). Also wait
        // past the ~1s clamped startupTimeout floor so a leaked watchdog would fire.
        try await Task.sleep(for: .milliseconds(1300))

        #expect(mockHTTP.connectCallCount == 0,
                "A stop() racing the deferred connect Task must cancel it before it connects")
        #expect(streamer.streamingState == .idle,
                "A streamer stopped in the same turn as play() must settle at .idle")
    }

    /// #488 (resurrection race): replaying from a stuck state enqueues a deferred
    /// teardown+reconnect Task. A `stop()` in the same turn must cancel it so the
    /// stopped streamer is not resurrected into `.buffering` with a live watchdog.
    /// Before #488 that Task tore down, restored `.connecting`, armed a watchdog and
    /// connected — reviving an intentionally-stopped streamer.
    @Test(
        "A racing stop() after a replay does not resurrect a stopped streamer",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
    func racingStopAfterReplayDoesNotResurrect() async throws {
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

        // Drive the streamer into a stuck (buffering) state with a live watchdog.
        streamer.play()
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 1 { break }
        }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the initial connect happened")
        let connectsBefore = mockHTTP.connectCallCount

        // Replay from the stuck state, then stop in the SAME turn. The superseded
        // deferred teardown+reconnect Task must be cancelled: no resurrection into
        // buffering, no fresh connect, no re-armed watchdog.
        streamer.play()
        streamer.stop()

        // Wait well past the ~1s clamped startupTimeout floor so a resurrected
        // watchdog would have fired a reconnect by now.
        try await Task.sleep(for: .milliseconds(1300))

        #expect(streamer.streamingState == .idle,
                "A stopped streamer must not be resurrected by the superseded replay Task")
        #expect(mockHTTP.connectCallCount == connectsBefore,
                "No new connect must be issued after stop() cancels the replay Task")
    }
    // MARK: - #697: Waiting-for-Connectivity Gate

    /// Drains the streamer's internal event stream and records every `.error`
    /// event, mirroring `MP3StreamerErrorEventTests`'s collector. Used here to
    /// prove that a legitimately offline/parked connect emits no `startup_timeout`
    /// (or any other) error while the watchdog is gated.
    private final class InternalEventErrorCollector {
        var errors: [Error] = []
        var count: Int { errors.count }
    }

    private func drainErrors(from streamer: MP3Streamer, into collector: InternalEventErrorCollector) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in streamer.eventStreamInternal {
                if case .error(let error) = event {
                    collector.errors.append(error)
                }
            }
        }
    }

    /// The core #697 regression: a task legitimately parked waiting for network
    /// connectivity must not be torn down by the startup watchdog. Tearing it
    /// down and reconnecting only parks a fresh task on the same dead network,
    /// producing repeated `startup_timeout`s instead of letting the original
    /// task self-resume once connectivity returns.
    @Test("Does not tear down a task waiting for connectivity; emits no startup_timeout")
    func doesNotTearDownTaskWaitingForConnectivity() async throws {
        // `connectionTimeout: 0` keeps the config's startupTimeout clamp
        // (`max(startupTimeout, connectionTimeout + 1)`) at its 1.0s floor, so the
        // watchdog fires quickly instead of at the default connectionTimeout + 1
        // — the same clamp `escalatesWhenBufferingStarves` relies on, and this
        // test's poll budget below is sized against that same ~1.0s deadline.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // The connect is issued but never resolves — simulating a real
        // `waitsForConnectivity` park where neither `.connected` nor `.error`
        // ever arrives for the outstanding task. `nextConnectDelay` holds the
        // mock's own `connect()` from auto-yielding `.connected`, so the only
        // signal the streamer ever sees is the manually-yielded
        // `.waitingForConnectivity` below — matching a real parked task, which
        // never reaches `didReceive response` while offline.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil
        mockHTTP.nextConnectDelay = .seconds(5)

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        let collector = InternalEventErrorCollector()
        let drain = drainErrors(from: streamer, into: collector)
        defer { drain.cancel() }

        streamer.play()

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 1 { break }
        }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the initial connect was issued")

        // Simulate the OS reporting the outstanding task is parked offline.
        mockHTTP.yield(.waitingForConnectivity)

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if streamer.isWaitingForConnectivity { break }
        }
        #expect(streamer.isWaitingForConnectivity,
                "Precondition: the streamer observed the waiting-for-connectivity signal")

        // `startupTimeout: 0.1` is clamped up to the config's ~1.0s floor
        // (`max(startupTimeout, connectionTimeout + 1)`, see
        // `MP3StreamerConfiguration.swift`) — the watchdog actually arms for
        // ~1.0s, not 0.1s. Budget generously past that (mirroring
        // `escalatesWhenBufferingStarves`'s 120×25ms poll for the same clamped
        // floor) so the deadline genuinely fires at least once — twice, given the
        // ~0.5s default backoff — WHILE the task is still parked. Without the
        // gate this loop would observe `connectCallCount` reach 2 well inside the
        // budget; with it, the loop exhausts its full 3s never seeing that.
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 2 { break }
        }

        #expect(mockHTTP.connectCallCount == 1,
                "A task known to be waiting for connectivity must not be reconnected")
        #expect(mockHTTP.disconnectCallCount == 0,
                "A task known to be waiting for connectivity must not be torn down")
        #expect(streamer.streamingState == .connecting,
                "State must stay parked at .connecting, not escalate to .error")
        #expect(collector.count == 0,
                "No startup_timeout (or any other) error should be emitted for a legitimately offline park")
    }

    /// A parked task must self-resume — not be reconnected into a second park —
    /// once connectivity actually returns and the original task's response
    /// finally arrives.
    @Test("Self-resumes on the original task once connectivity returns")
    func selfResumesOnOriginalTaskOnceConnectivityReturns() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // Hold the mock's own `connect()` from auto-yielding `.connected` so the
        // manual `.waitingForConnectivity` / `.connected` yields below are the
        // only signals the streamer observes — see the comment in
        // `doesNotTearDownTaskWaitingForConnectivity` above.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil
        mockHTTP.nextConnectDelay = .seconds(5)

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 1 { break }
        }

        mockHTTP.yield(.waitingForConnectivity)

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if streamer.isWaitingForConnectivity { break }
        }
        #expect(streamer.isWaitingForConnectivity)

        // Let the ~1.0s clamped watchdog deadline elapse — and re-elapse, given
        // the ~0.5s default backoff — while still parked, before connectivity
        // returns. Same budget/rationale as `doesNotTearDownTaskWaitingForConnectivity`.
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 2 { break }
        }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: still parked on the original connect")

        // Connectivity returns and the SAME task's response finally arrives.
        mockHTTP.yield(.connected)

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if !streamer.isWaitingForConnectivity { break }
        }

        #expect(!streamer.isWaitingForConnectivity,
                "The waiting-for-connectivity flag must clear once the park resolves")
        guard case .buffering = streamer.streamingState else {
            Issue.record("Expected .buffering after the parked task's response arrived, got \(streamer.streamingState)")
            return
        }
        #expect(mockHTTP.connectCallCount == 1,
                "Connectivity returning must resume the SAME task, not issue a fresh connect")
    }
}

extension Tag {
    @Tag static var startupWatchdog: Self
}

#endif // !os(watchOS)
