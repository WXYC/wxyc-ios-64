//
//  PlaybackHeartbeatTests.swift
//  Playback
//
//  Behavior tests for the periodic `playback_heartbeat` cadence (#666) on
//  both PlaybackController implementations. `play`/`pause` alone under-count
//  listening-hours: the longest sessions — the app swiped away,
//  OS-terminated in the background, or crashed — never fire a `pause`, so
//  they contribute zero recorded duration. These tests prove a killed,
//  never-paused session still yields a reconstructable duration from
//  `max(cumulative_seconds)` across its heartbeats, and that the cadence
//  starts/stops exactly with genuine playback (no leaked timer once
//  playback stops, stalls, or is interrupted).
//
//  Driven by `StartupWatchdogGate` (#787, reused per #807/#815) rather than
//  real wall-clock sleeps: a ~10s process stall blew every wall-clock-bounded
//  wait in this suite in CI run 31205214380 — a 30ms cadence measured against
//  a 2s deadline has no margin against a runner that stops scheduling the
//  test process at all. Gating each controller's heartbeat sleep lets a test
//  drive ticks by releasing the gate instead of waiting real time.
//
//  Two properties are load-bearing for every assertion below — both cost a
//  review round in #807 to get right, and the same reasoning applies here.
//  See `PlaybackHeartbeatComponentTests.swift` for the worked example this
//  file mirrors:
//
//  - `StartupWatchdogGate.sleep(for:)` is `nonisolated`. A `release()` only
//    resumes a `CheckedContinuation`, which re-enqueues the awaiting task's
//    remaining body onto its own actor — it does not run the tick's effects
//    inline. A `heartbeatEvents` read taken immediately after `release()` or
//    a stop/stall/interruption, with no intervening suspension point, checks
//    nothing. Every assertion that needs to observe a tick's effect awaits a
//    second `waitForArm()` first (proof the tick already ran and the loop
//    re-armed); every negative assertion checks synchronous gate state
//    (`pendingArmCount`, which `Task.cancel()`'s cancellation handler updates
//    synchronously) instead of a heartbeat count.
//  - Each `PlaybackHeartbeat` instance runs at most one loop at a time — its
//    own `start()` cancels any prior task before installing a new one — so
//    there is no "two loops racing to park" ambiguity here the way a
//    `restartCollapsesToSingleTimer`-style test would need to guard against.
//
//  Created by Jake Bromberg on 07/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
#if canImport(UIKit)
import UIKit
#endif
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule

@Suite("Playback Heartbeat Tests")
@MainActor
struct PlaybackHeartbeatTests {

    /// Only meaningful as documentation now that ticks are gate-driven rather
    /// than timed — nothing in this suite waits out a real interval — but it
    /// still stands in for the production cadence in the durations recorded
    /// on `StartupWatchdogGate.requestedDurations`.
    private static let testInterval: Duration = .milliseconds(30)

    /// Advances the heartbeat by one gate-driven tick and proves it landed:
    /// releases the currently-parked arm, then waits for the loop to re-arm,
    /// which only happens after `onTick()` has run and the loop has looped
    /// back into a fresh sleep. Mirrors `PlaybackHeartbeatComponentTests`.
    private func advanceOneTick(_ gate: StartupWatchdogGate) async throws {
        try await gate.waitForArm(timeout: stallTolerantTimeout)
        gate.release()
        try await gate.waitForArm(timeout: stallTolerantTimeout)
    }

    // MARK: - Kill-robust duration reconstruction

    @Test(
        "A never-paused session emits reconstructable heartbeats sharing the play event's session id",
        arguments: PlayerControllerTestCase.allCases
    )
    func neverPausedSessionEmitsReconstructableHeartbeats(testCase: PlayerControllerTestCase) async throws {
        let gate = StartupWatchdogGate()
        let harness = PlayerControllerTestHarness.make(for: testCase, heartbeatInterval: Self.testInterval, heartbeatSleep: gate.sleep)
        await harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let startedSessionID = try #require(
            harness.mockAnalytics.startedEvents.last?.sessionID,
            "play() should capture a session id"
        )

        // Advance past several heartbeat ticks with NO pause — modeling the
        // app being killed mid-listen (swiped away, OS-terminated, crashed)
        // so the session never reaches a clean stop.
        for _ in 0..<3 {
            try await advanceOneTick(gate)
        }

        let heartbeats = harness.heartbeatEvents
        #expect(heartbeats.count >= 3, "Expected at least 3 heartbeats, got \(heartbeats.count)")
        #expect(harness.mockAnalytics.stoppedEvents.isEmpty, "This scenario must never fire a pause — that's the whole point")

        let lastHeartbeat = try #require(heartbeats.last)
        #expect(lastHeartbeat.sessionID == startedSessionID,
               "Every heartbeat must carry the same session id as the play event it belongs to")
        #expect(lastHeartbeat.cumulativeSeconds > 0,
               "The last heartbeat before a kill is the reconstructed duration for this listen, so it must be positive")
        #expect(lastHeartbeat.context == .foreground)

        let expectedPlayerType: PlayerControllerType = testCase == .radioPlayerController ? .radioPlayer : .mp3Streamer
        #expect(lastHeartbeat.playerType == expectedPlayerType)

        harness.controller.stop()
        gate.releaseAll()
    }

    @Test(
        "Heartbeats fire at the fixed cadence while playing: cumulative_seconds strictly increases tick over tick",
        arguments: PlayerControllerTestCase.allCases
    )
    func heartbeatsFireAtFixedCadence(testCase: PlayerControllerTestCase) async throws {
        let gate = StartupWatchdogGate()
        let harness = PlayerControllerTestHarness.make(for: testCase, heartbeatInterval: Self.testInterval, heartbeatSleep: gate.sleep)
        await harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // `cumulativeSeconds` comes from a real monotonic clock read
        // (`Core.Timer`, backed by `ContinuousClock`) inside each
        // controller — the gate only decides *when* a tick's onTick() runs,
        // not what it reads. Strict-increase is therefore a genuine duration
        // property, not a cadence one, and gate-driving the tick count alone
        // would leave it resting on an unstated assumption: that some
        // non-zero wall-clock time happens to separate two ticks fired back
        // to back with no minimum spacing between them. A 1ms real sleep
        // between ticks makes that separation explicit and guaranteed
        // instead of incidental. This is not a deadline — nothing times out
        // or is asserted against how long it takes — so it cannot reintroduce
        // the false-RED exposure this conversion removes; it exists solely
        // so the assertion below keeps its power to catch a frozen/corrupted
        // duration source instead of silently degrading into one that would
        // pass even against a bug that always reports the same value.
        for _ in 0..<3 {
            try await advanceOneTick(gate)
            try await Task.sleep(for: .milliseconds(1))
        }

        let heartbeats = harness.heartbeatEvents
        try #require(heartbeats.count >= 3)

        // Each successive heartbeat reflects strictly more elapsed playing
        // time than the last — proof the duration source is actually a live
        // monotonic clock, not a frozen or re-emitted value.
        for index in 1..<3 {
            #expect(heartbeats[index].cumulativeSeconds > heartbeats[index - 1].cumulativeSeconds,
                   "Heartbeat \(index) should report more elapsed time than heartbeat \(index - 1)")
        }

        harness.controller.stop()
        gate.releaseAll()
    }

    // MARK: - Prompt cancellation (no leaked timer)

    @Test(
        "Heartbeat stops promptly on a genuine stop — no further heartbeats leak through",
        arguments: PlayerControllerTestCase.allCases
    )
    func heartbeatStopsOnGenuineStop(testCase: PlayerControllerTestCase) async throws {
        let gate = StartupWatchdogGate()
        let harness = PlayerControllerTestHarness.make(for: testCase, heartbeatInterval: Self.testInterval, heartbeatSleep: gate.sleep)
        await harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        try await advanceOneTick(gate)
        try #require(harness.heartbeatEvents.count >= 1)

        try harness.controller.toggle(reason: .testToggle)
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        // Not a `Task.sleep` window followed by a count comparison: resuming
        // a continuation only re-enqueues the awaiting task's body onto the
        // main actor, and with no suspension point between `stop()` and the
        // read, a `heartbeatEvents.count` check would pass unchanged whether
        // or not the loop actually leaked — the false-GREEN this issue
        // exists to fix. `pendingArmCount` needs no suspension point:
        // `stop()`'s `task?.cancel()` invokes the gate's `onCancel` handler
        // synchronously, retiring the arm before `stop()` even returns, so a
        // stop that dropped the task reference without cancelling it is
        // caught deterministically instead of by hoping a leaked tick gets
        // scheduled inside a fixed window.
        #expect(gate.pendingArmCount == 0,
               "A genuine stop must retire the pending heartbeat sleep, not merely drop the task reference")

        gate.releaseAll()
    }

    @Test(
        "Heartbeat stops promptly on a stall — no further heartbeats until a genuine recovery",
        arguments: PlayerControllerTestCase.allCases
    )
    func heartbeatStopsOnStall(testCase: PlayerControllerTestCase) async throws {
        let gate = StartupWatchdogGate()
        let harness = PlayerControllerTestHarness.make(for: testCase, heartbeatInterval: Self.testInterval, heartbeatSleep: gate.sleep)
        await harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        try await advanceOneTick(gate)
        try #require(harness.heartbeatEvents.count >= 1)

        harness.simulateStall()
        await harness.waitForAsync()

        // See `heartbeatStopsOnGenuineStop` for why this is `pendingArmCount`
        // rather than a sleep-then-count comparison.
        #expect(gate.pendingArmCount == 0,
               "A stall must retire the pending heartbeat sleep, not merely drop the task reference")

        harness.controller.stop()
        gate.releaseAll()
    }

    #if os(iOS)
    @Test("Heartbeat stops promptly on an interruption — no further heartbeats until auto-resume")
    func heartbeatStopsOnInterruption() async throws {
        // Interruption analytics/session behavior is only exercised through
        // AudioPlayerController's NotificationCenter-driven path in this
        // harness (mirrors SessionIdentityTests.interruptionAutoResumePreservesSessionID).
        let gate = StartupWatchdogGate()
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController, heartbeatInterval: Self.testInterval, heartbeatSleep: gate.sleep)
        await harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        try await advanceOneTick(gate)
        try #require(harness.heartbeatEvents.count >= 1)

        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        // See `heartbeatStopsOnGenuineStop` for why this is `pendingArmCount`
        // rather than a sleep-then-count comparison.
        #expect(gate.pendingArmCount == 0,
               "An interruption must retire the pending heartbeat sleep, not merely drop the task reference")

        harness.controller.stop()
        gate.releaseAll()
    }
    #endif
}
