//
//  PlaybackHeartbeatComponentTests.swift
//  Playback
//
//  Direct unit tests for the extracted `PlaybackHeartbeat` component (#755) —
//  the cancel-then-loop-sleep-emit task shape shared by AudioPlayerController
//  and RadioPlayerController. These exercise the component in isolation, no
//  controller involved; `Behavior/PlaybackHeartbeatTests.swift` covers the
//  same cadence end-to-end through both controllers.
//
//  Driven by `StartupWatchdogGate` (#787, reused here per #807) rather than
//  real wall-clock sleeps: a ~10s process stall blew every wall-clock-bounded
//  wait in this suite in CI run 31205214380, because a 30ms cadence measured
//  against a 2-5s deadline has no margin against a runner that stops
//  scheduling the test process at all. Gating `start()`'s sleep lets a test
//  drive ticks by releasing the gate instead of waiting real time, so the
//  suite is immune to scheduler starvation rather than merely tolerant of a
//  wider one.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
@testable import PlaybackCore

@Suite("PlaybackHeartbeat Component Tests")
@MainActor
struct PlaybackHeartbeatComponentTests {

    /// Only meaningful as documentation now that ticks are gate-driven rather
    /// than timed — nothing in this suite waits out a real interval — but it
    /// still stands in for the production cadence in the durations recorded
    /// on `StartupWatchdogGate.requestedDurations`.
    private static let testInterval: Duration = .milliseconds(30)

    @Test("start() ticks repeatedly at the configured interval")
    func startTicksRepeatedly() async throws {
        let gate = StartupWatchdogGate()
        var tickCount = 0
        let heartbeat = PlaybackHeartbeat(interval: Self.testInterval, sleep: gate.sleep) {
            tickCount += 1
        }

        heartbeat.start()
        for _ in 0..<3 {
            try await gate.waitForArm()
            gate.release()
        }
        // The third release's tick has fired by the time the loop re-arms —
        // waiting for one more arm proves it happened rather than assuming it.
        try await gate.waitForArm()

        #expect(tickCount >= 3)

        heartbeat.stop()
    }

    @Test("stop() cancels the loop — no further ticks")
    func stopCancelsLoop() async throws {
        let gate = StartupWatchdogGate()
        var tickCount = 0
        let heartbeat = PlaybackHeartbeat(interval: Self.testInterval, sleep: gate.sleep) {
            tickCount += 1
        }

        heartbeat.start()
        try await gate.waitForArm()
        gate.release()
        // Waiting for the second arm proves the first tick already fired and
        // the loop looped back into a fresh sleep — the arm this stop() is
        // about to cancel.
        try await gate.waitForArm()
        try #require(tickCount == 1)

        heartbeat.stop()
        let countAtStop = tickCount

        // The cancelled arm retires (StartupWatchdogGateTests pins this), so
        // this release has nothing to resume and is banked instead — proof
        // that stop() actually cancelled the parked sleep rather than merely
        // racing it.
        gate.release()

        #expect(tickCount == countAtStop, "No tick should fire after stop()")
    }

    @Test("stop() before start() is a safe no-op")
    func stopWithoutStartIsNoOp() {
        var tickCount = 0
        let heartbeat = PlaybackHeartbeat(interval: Self.testInterval) {
            tickCount += 1
        }

        heartbeat.stop()

        #expect(tickCount == 0)
    }

    @Test("start() is idempotent — a redundant call collapses to a single live timer")
    func restartCollapsesToSingleTimer() async throws {
        let gate = StartupWatchdogGate()
        var tickCount = 0
        let heartbeat = PlaybackHeartbeat(interval: Self.testInterval, sleep: gate.sleep) {
            tickCount += 1
        }

        // Start, then immediately restart before the first interval elapses.
        // A correct implementation cancels the first loop and begins timing
        // fresh from the second `start()`, so exactly one loop is alive.
        heartbeat.start()
        heartbeat.start()

        // Under real wall-clock sleeps this used to be inferred from tick
        // *rate*: a stacked second loop delivers two ticks per interval, so
        // it reaches any given count in half the time. That inference needed
        // a wall-clock floor, which is exactly what made it fail under a
        // process stall (#807). Under the gate the inference is unnecessary —
        // every `release()` resumes exactly one parked arm no matter how many
        // loops are alive, so the tick rate stops discriminating and the
        // parked-arm count becomes the direct, deterministic statement of the
        // property: a stacked pair would show two arms parked here, not one.
        try await gate.waitForArm()
        #expect(gate.pendingArmCount == 1, "start() called twice left \(gate.pendingArmCount) arms parked — a stacked loop, not a single collapsed one")

        gate.release()
        try await gate.waitForArm()
        #expect(tickCount == 1, "The surviving loop should still be ticking")

        heartbeat.stop()
    }

    @Test("a heartbeat released without stop() stops ticking")
    func releasedHeartbeatStopsTicking() async throws {
        let gate = StartupWatchdogGate()
        var tickCount = 0

        do {
            let heartbeat = PlaybackHeartbeat(interval: Self.testInterval, sleep: gate.sleep) {
                tickCount += 1
            }
            // Hardening, not the fix: Swift does not guarantee a binding's
            // lexical lifetime, so an aggressive optimizer is free to release
            // `heartbeat` after what it can prove is its last use rather than
            // at the end of this `do` block. This keeps `heartbeat` alive
            // through the block's true end regardless. It guards against
            // unspecified ARC release timing and was *not* the cause of run
            // 31205214380 (#807) — three of the four failing tests used
            // `heartbeat` after the point premature release would have fired,
            // which rules it out as an explanation for any of them.
            defer { withExtendedLifetime(heartbeat) {} }

            heartbeat.start()
            try await gate.waitForArm()
            gate.release()
            // Proves the tick already fired: the loop only re-arms after
            // `onTick()` runs.
            try await gate.waitForArm()
            try #require(tickCount == 1)
            // Deliberately no `stop()` — the instance is released here, which
            // is the whole point. The loop captures `interval` and `onTick`
            // by value and never touches `self`, so nothing about the task
            // itself notices the owner is gone; only `deinit` does.
        }

        let countAtRelease = tickCount
        // `deinit` cancels the task, which retires this pending arm exactly
        // as `stop()`'s cancellation does above. A release consumed here
        // would mean the loop is still alive — the leak itself, not a timing
        // artifact — so it is banked instead of resumed.
        gate.release()

        #expect(tickCount == countAtRelease, "A released heartbeat must not keep ticking forever")
    }
}
