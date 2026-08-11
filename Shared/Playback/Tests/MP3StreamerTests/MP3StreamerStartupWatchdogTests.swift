//
//  MP3StreamerStartupWatchdogTests.swift
//  Playback
//
//  Tests for the startup watchdog that escalates when playback connects but
//  never reaches the .playing state (Sentry IOS-31: "Playback not starting").
//
//  Driven by a `StartupWatchdogGate` (see #787/#807) rather than the wall
//  clock. Every test in this file previously drove `MP3Streamer` with its real
//  `startupTimeout` and polled `Task.sleep` loops hoping the watchdog's
//  ~1s-clamped deadline had (or hadn't) elapsed by the time the poll budget
//  ran out — under MainActor scheduling contention from a full-plan test run,
//  the deadline and the poll budget could each drift independently, producing
//  `connectCallCount` mismatches in both directions (#687). Gating the
//  watchdog's sleep means a deadline can never fire, defer, or re-arm except
//  in direct response to the test calling `release()`, so every assertion in
//  this file is now decided by explicit test action instead of by racing a
//  real clock against scheduler latency.
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
        // `connectionTimeout`/`startupTimeout` no longer control real timing —
        // the gate does — but are kept close to the values a live watchdog
        // would clamp to, since `StreamStartupError.timedOut(seconds:)` still
        // reports `configuration.startupTimeout`.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        // Connect succeeds, but no data ever arrives → stuck in buffering(0/5).
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            startupWatchdogSleep: gate.sleep
        )

        streamer.play()

        // Prove the watchdog actually armed, then fire its deadline directly —
        // no dependence on how long that takes to happen under load.
        try await gate.waitForArm()
        gate.release()

        // Without the watchdog, connectCallCount stays 1 forever. With it firing,
        // attemptReconnect() (first backoff wait is real but short) issues a
        // second connect.
        await pollUntil { mockHTTP.connectCallCount >= 2 }

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
        // Tiny backoff waits so successive escalation reconnects fire almost
        // immediately. This wait is real wall-clock (Task.sleep inside
        // attemptReconnect(), not gated) — kept tiny purely to keep the test fast.
        let backoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 10)
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        // Every connect succeeds at the HTTP layer but no data ever arrives → each
        // attempt parks in buffering(0/5) and starves.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            backoffTimer: backoff,
            startupWatchdogSleep: gate.sleep
        )

        streamer.play()

        // release() always removes the arm it resumes before returning, so a
        // waitForArm() right after it is unambiguous — it can only be observing
        // the NEXT arm, never a stale one. Two release/wait cycles: the first
        // escalates the initial starved connect into a reconnect (connect #2);
        // the second proves that reconnect's own starvation is watched too
        // (connect #3) — the pre-#487 regression plateaued at 2.
        try await gate.waitForArm()
        gate.release()

        try await gate.waitForArm()
        await pollUntil { mockHTTP.connectCallCount >= 2 }
        #expect(mockHTTP.connectCallCount >= 2, "Precondition: the first escalation issued a reconnect")

        gate.release()
        await pollUntil { mockHTTP.connectCallCount >= 3 }

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
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2,
            connectionTimeout: 0,
            startupTimeout: 0.3
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        // First connect starves; the escalation reconnect below is fed real data
        // so it can cross the buffer threshold into `.playing`.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            backoffTimer: backoff,
            startupWatchdogSleep: gate.sleep
        )

        streamer.play()

        // Precondition: reach the starved buffering phase before firing the
        // watchdog.
        try await gate.waitForArm()
        await pollUntil {
            if case .buffering = streamer.streamingState { return true }
            return false
        }
        guard case .buffering = streamer.streamingState else {
            Issue.record("Precondition: expected .buffering before firing the watchdog, got \(streamer.streamingState)")
            return
        }

        // Arm the recovery before firing: the next connect (the watchdog's
        // escalation reconnect) will feed real MP3 data.
        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        gate.release()

        await pollUntil { streamer.streamingState == .playing }

        guard case .playing = streamer.streamingState else {
            // Environment couldn't decode real MP3 — skip rather than fail.
            return
        }

        let connectsAtPlaying = mockHTTP.connectCallCount

        // Reaching .playing must cancel the re-armed watchdog outright — assert
        // on the gate's own state (no live arm left), not on a deadline that,
        // with the gate, can never fire on its own.
        await pollUntil { !gate.hasPendingArm }

        #expect(streamer.streamingState == .playing)
        #expect(!gate.hasPendingArm,
                "Reaching .playing on a reconnect must cancel the re-armed watchdog")
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
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2,
            startupTimeout: 5.0
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            startupWatchdogSleep: gate.sleep
        )

        streamer.play()

        // The gate's deadline is never released — a healthy start must reach
        // .playing and cancel the watchdog entirely on its own, with no
        // dependence on how long decoding real MP3 data takes.
        await pollUntil { streamer.streamingState == .playing }

        guard case .playing = streamer.streamingState else {
            // Environment couldn't decode real MP3 — skip rather than fail.
            return
        }

        await pollUntil { !gate.hasPendingArm }

        #expect(streamer.streamingState == .playing)
        #expect(!gate.hasPendingArm,
                "Watchdog must be cancelled on reaching .playing, not left armed")
        #expect(mockHTTP.connectCallCount == 1,
                "Watchdog must be cancelled on reaching .playing, not issue a reconnect")
    }

    /// Stopping before the deadline must cancel the watchdog so it can't fire a
    /// reconnect against an intentionally-stopped streamer.
    @Test("Is cancelled by stop() before it can fire")
    func cancelledByStop() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            startupWatchdogSleep: gate.sleep
        )

        streamer.play()

        // Wait until the watchdog is provably armed before stopping. Formerly
        // `.disabled(if: WXYC_SKIP_KNOWN_FLAKES == "1")` (#371/#687): the
        // wall-clock version approximated "armed" with `connectCallCount == 1`
        // and stopped on a poll racing the real ~1s deadline, which under load
        // could already have fired by the time the poll noticed. Observing the
        // gate directly removes that race rather than widening its budget.
        try await gate.waitForArm()

        streamer.stop()

        // No live deadline remains to gate — stop() must have cancelled it
        // synchronously as part of cancelStartupWatchdog(). Poll rather than
        // assert immediately: the cancellation handler can lag the cancel()
        // call by a scheduler hop.
        await pollUntil { !gate.hasPendingArm }

        #expect(streamer.streamingState == .idle)
        #expect(!gate.hasPendingArm,
                "A stopped streamer must not leave a live startup watchdog behind")
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
    @Test("Escalation cancels an in-flight reconnect instead of leaking it")
    func escalationCancelsInFlightReconnect() async throws {
        let backoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 1)
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.2)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            backoffTimer: backoff,
            startupWatchdogSleep: gate.sleep
        )

        streamer.play()

        // Reach buffering — the initial connect completes.
        try await gate.waitForArm()
        await pollUntil { mockHTTP.connectCompletedCount == 1 }
        #expect(mockHTTP.connectCompletedCount == 1, "Precondition: the initial connect completed")
        let armsAfterInitialConnect = gate.requestedDurations.count

        // A mid-startup disconnect schedules a reconnect whose connect() hangs
        // briefly, so it is still in flight when the watchdog fires and
        // escalates. The hang only needs to outlast the settle time checked
        // below, not any watchdog deadline — nothing can escalate before the
        // test explicitly releases the gate, unlike the wall-clock version,
        // which needed this hang to outlast the watchdog's own ~1s floor.
        mockHTTP.nextConnectDelay = .milliseconds(300)
        mockHTTP.yield(.disconnected)

        // The disconnect's own attemptReconnect() supersedes the play()-time arm
        // (armStartupWatchdog() self-cancels it) and re-arms once its backoff
        // wait elapses — that re-arm is the one spanning the now-in-flight, hung
        // reconnect. `requestedDurations.count` increasing is unambiguous
        // evidence of THIS specific re-arm: unlike `hasPendingArm` alone, which
        // the superseded arm could still satisfy for a moment after the
        // disconnect but before its own cancellation is processed, the count is
        // updated in the same critical section as the disposition decision (see
        // `StartupWatchdogGate.sleep(for:)`).
        await pollUntil { gate.requestedDurations.count > armsAfterInitialConnect }
        gate.release()

        // The watchdog's escalation must cancel the in-flight reconnect rather
        // than let it run to completion.
        await pollUntil { mockHTTP.connectCallCount >= 2 }
        #expect(mockHTTP.connectCallCount == 2,
                "The mid-startup disconnect must have issued exactly one reconnect")

        // Let the (cancelled) hung connect's own early-return settle — bounded
        // by the mock's own artificial hang, not by any production deadline, so
        // this isn't the wall-clock coupling #687 is about.
        try await Task.sleep(for: .milliseconds(400))

        #expect(mockHTTP.connectCompletedCount == 1,
                "Watchdog escalation must cancel the in-flight reconnect, not leak it to completion")
    }

    /// #488 (fresh-play race): `play()` enqueues a deferred connect Task; a `stop()`
    /// landing in the SAME MainActor turn — before that Task drains — must cancel the
    /// pending connect. Before #488 the deferred Task was un-stored, so `stop()` could
    /// not cancel it: the stopped streamer still issued a connect and armed a watchdog.
    @Test("A racing stop() cancels the deferred connect before it fires")
    func racingStopBeforeDeferredConnectDrains() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            startupWatchdogSleep: gate.sleep
        )

        // play() then stop() in the SAME synchronous MainActor turn — no await
        // between them — so the deferred connect Task has not run yet when
        // stop() lands.
        streamer.play()
        streamer.stop()

        // The deferred connect Task's very first line checks Task.isCancelled
        // before doing anything else, so it either never starts or returns
        // immediately without reaching armStartupWatchdog() — there is no
        // window in which it can proceed past that guard. A few yields drain
        // the MainActor queue far enough for that immediate return to actually
        // run; nothing here depends on elapsed wall-clock time.
        for _ in 0..<5 { await Task.yield() }

        #expect(mockHTTP.connectCallCount == 0,
                "A stop() racing the deferred connect Task must cancel it before it connects")
        #expect(streamer.streamingState == .idle,
                "A streamer stopped in the same turn as play() must settle at .idle")
        #expect(!gate.hasPendingArm,
                "The cancelled deferred connect Task must never reach armStartupWatchdog()")
    }

    /// #488 (resurrection race): replaying from a stuck state enqueues a deferred
    /// teardown+reconnect Task. A `stop()` in the same turn must cancel it so the
    /// stopped streamer is not resurrected into `.buffering` with a live watchdog.
    /// Before #488 that Task tore down, restored `.connecting`, armed a watchdog and
    /// connected — reviving an intentionally-stopped streamer.
    @Test("A racing stop() after a replay does not resurrect a stopped streamer")
    func racingStopAfterReplayDoesNotResurrect() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            startupWatchdogSleep: gate.sleep
        )

        // Drive the streamer into a stuck (buffering) state with a live watchdog.
        streamer.play()
        try await gate.waitForArm()
        await pollUntil { mockHTTP.connectCallCount >= 1 }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the initial connect happened")
        let connectsBefore = mockHTTP.connectCallCount

        // Replay from the stuck state, then stop in the SAME turn. The superseded
        // deferred teardown+reconnect Task must be cancelled: no resurrection into
        // buffering, no fresh connect, no re-armed watchdog.
        streamer.play()
        streamer.stop()

        // stop() cancels the still-parked watchdog from the FIRST play() directly;
        // the replay's own deferred Task is cancelled before it can reach a second
        // armStartupWatchdog() call — same reasoning as
        // racingStopBeforeDeferredConnectDrains. A few yields drain that.
        for _ in 0..<5 { await Task.yield() }

        #expect(streamer.streamingState == .idle,
                "A stopped streamer must not be resurrected by the superseded replay Task")
        #expect(mockHTTP.connectCallCount == connectsBefore,
                "No new connect must be issued after stop() cancels the replay Task")
        #expect(!gate.hasPendingArm,
                "No watchdog may remain armed — the original was cancelled by stop() and the replay's Task never reached a second arm")
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
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        // The connect is issued but never resolves — simulating a real
        // `waitsForConnectivity` park where neither `.connected` nor `.error`
        // ever arrives for the outstanding task. `nextConnectDelay` holds the
        // mock's own `connect()` from auto-yielding `.connected`, so the only
        // signal the streamer ever sees is the manually-yielded
        // `.waitingForConnectivity` below — matching a real parked task, which
        // never reaches `didReceive response` while offline.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil
        mockHTTP.nextConnectDelay = .seconds(30)

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            startupWatchdogSleep: gate.sleep
        )

        let collector = InternalEventErrorCollector()
        let drain = drainErrors(from: streamer, into: collector)
        defer { drain.cancel() }

        streamer.play()

        try await gate.waitForArm()
        await pollUntil { mockHTTP.connectCallCount >= 1 }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the initial connect was issued")

        // Simulate the OS reporting the outstanding task is parked offline.
        mockHTTP.yield(.waitingForConnectivity)

        await pollUntil { streamer.isWaitingForConnectivity }
        #expect(streamer.isWaitingForConnectivity,
                "Precondition: the streamer observed the waiting-for-connectivity signal")

        // Fire the watchdog's deadline twice while still parked. Each fire must
        // defer (not escalate) and re-arm — proven directly by waiting for the
        // NEXT arm after each release (safe: release() always removes the arm
        // it resumes before returning, so a following waitForArm() can only be
        // observing a genuinely new one), rather than hoping the wall clock
        // produces a couple of fires inside a fixed budget. That hope is
        // exactly #687's actual failure mode: under load, it sometimes didn't
        // pay off in either direction.
        for _ in 0..<2 {
            gate.release()
            try await gate.waitForArm()
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
        let gate = StartupWatchdogGate()
        defer { gate.releaseAll() }

        // Hold the mock's own `connect()` from auto-yielding `.connected` so the
        // manual `.waitingForConnectivity` / `.connected` yields below are the
        // only signals the streamer observes — see the comment in
        // `doesNotTearDownTaskWaitingForConnectivity` above.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil
        mockHTTP.nextConnectDelay = .seconds(30)

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            startupWatchdogSleep: gate.sleep
        )

        streamer.play()

        try await gate.waitForArm()
        await pollUntil { mockHTTP.connectCallCount >= 1 }

        mockHTTP.yield(.waitingForConnectivity)

        await pollUntil { streamer.isWaitingForConnectivity }
        #expect(streamer.isWaitingForConnectivity)

        // Same rigor as doesNotTearDownTaskWaitingForConnectivity: fire the
        // watchdog twice while parked, proving each fire defers and re-arms
        // rather than escalating, before connectivity ever returns.
        for _ in 0..<2 {
            gate.release()
            try await gate.waitForArm()
        }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: still parked on the original connect")

        // Connectivity returns and the SAME task's response finally arrives.
        mockHTTP.yield(.connected)

        await pollUntil { !streamer.isWaitingForConnectivity }

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
