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
//  drive ticks by releasing the gate instead of waiting real time.
//
//  Two properties are load-bearing for every assertion below, and both cost
//  a review round to get right (#807):
//
//  - `StartupWatchdogGate.sleep(for:)` is `nonisolated`. A `release()` only
//    resumes a `CheckedContinuation`, which re-enqueues the awaiting task's
//    remaining body onto its own actor (`@MainActor`, here) — it does not
//    run `onTick()` inline. A `tickCount` read taken immediately after
//    `release()`/`stop()`, with no intervening suspension point, checks
//    nothing: the enqueued job hasn't had a turn to run yet, so the read
//    is unchanged whether the loop is healthy or leaked. Every assertion
//    that needs to observe a tick's *effect* either awaits a second
//    `waitForArm()` first (proof the tick already ran and the loop
//    re-armed) or checks synchronous gate state (`pendingArmCount`, which
//    `Task.cancel()`'s cancellation handler updates synchronously) instead
//    of `tickCount`.
//  - `waitForArm()` returns the instant *one* arm parks. Two independent
//    loops each call the same `nonisolated` `sleep(for:)` — there is no
//    ordering guarantee that a second, stacked loop has also parked by
//    the time the first one satisfies a poll. Distinguishing "one loop"
//    from "two stacked loops" needs a quiescence point both loops are
//    guaranteed to have passed — `requestedDurations.count`, which grows
//    synchronously on *entry* to `sleep(for:)`, before either loop's own
//    suspension — not a race against whichever arm parks first.
//
//  `waitForArm` and `pollUntil` both default to a 5s timeout — half the
//  measured 10.5s stall (#807) — so every call below passes an explicit
//  `stallTolerantTimeout` instead. Without it, the suite would trade one
//  wall-clock vulnerability for a smaller one.
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

    /// Bound for every `waitForArm`/`pollUntil` call in this suite. Raised
    /// from the gate's and `pollUntil`'s shared 5s default — half the
    /// ~10.5s stall measured in CI run 31205214380 (#807) — to 30s, the
    /// same bound and derivation `PauseResponsivenessTests` uses. A suite
    /// that removed the wall clock from ticking but still bounded its own
    /// synchronization on a sub-stall wall-clock timeout would have merely
    /// moved the vulnerability, not closed it.
    private static let stallTolerantTimeout: Duration = .seconds(30)

    @Test("start() ticks repeatedly at the configured interval")
    func startTicksRepeatedly() async throws {
        let gate = StartupWatchdogGate()
        var tickCount = 0
        let heartbeat = PlaybackHeartbeat(interval: Self.testInterval, sleep: gate.sleep) {
            tickCount += 1
        }

        heartbeat.start()
        for _ in 0..<3 {
            try await gate.waitForArm(timeout: Self.stallTolerantTimeout)
            gate.release()
        }
        // The third release's tick has fired by the time the loop re-arms —
        // waiting for one more arm proves it happened rather than assuming it.
        try await gate.waitForArm(timeout: Self.stallTolerantTimeout)

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
        try await gate.waitForArm(timeout: Self.stallTolerantTimeout)
        gate.release()
        // Waiting for the second arm proves the first tick already fired and
        // the loop looped back into a fresh sleep — the arm this stop() is
        // about to cancel.
        try await gate.waitForArm(timeout: Self.stallTolerantTimeout)
        try #require(tickCount == 1)

        heartbeat.stop()

        // Not `gate.release()` + a `tickCount` read: resuming a continuation
        // only re-enqueues the awaiting task's body onto the main actor —
        // with no suspension point between `stop()` and the assertion, that
        // enqueued job (if it existed) would not have run yet, so `tickCount`
        // would read unchanged whether or not the loop actually leaked. A
        // `stop()` that assigned `task = nil` without calling `.cancel()`
        // would leave this arm parked forever and still pass such a check.
        // `pendingArmCount` needs no suspension point: `Task.cancel()`
        // invokes the gate's `onCancel` handler synchronously, retiring the
        // arm before `stop()` even returns.
        #expect(gate.pendingArmCount == 0, "stop() must retire the pending sleep, not merely drop the task reference")

        // Drains the arm if the check above just failed (a leaked arm would
        // otherwise strand a `CheckedContinuation` past this test's lifetime).
        gate.releaseAll()
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
        // process stall (#807).
        //
        // Under the gate, `pendingArmCount` is the direct statement of the
        // property — but only once BOTH loops have had a chance to reach
        // `sleep(for:)`. `waitForArm()` returns the instant ONE arm parks,
        // and because `sleep` is `nonisolated`, a stacked second loop parks
        // independently of the polling `pollUntil` inside `waitForArm()` —
        // there is no guarantee the second loop has parked by the time the
        // first satisfies the poll. `requestedDurations.count` is the
        // quiescence point instead: it grows synchronously on *entry* to
        // `sleep(for:)`, in the same uninterrupted synchronous prefix that
        // parks the arm a few lines later, with no suspension point between
        // the two — so observing it reach 2 on the main actor guarantees
        // both loops have also already reached their parking decision
        // (whether that decision is "park" or, for a properly-cancelled
        // first loop, "retire without parking at all").
        await pollUntil({ gate.requestedDurations.count == 2 }, timeout: Self.stallTolerantTimeout)
        try #require(gate.requestedDurations.count == 2, "not both start() loops reached sleep(for:) — pendingArmCount below would be meaningless")
        #expect(gate.pendingArmCount == 1, "start() called twice left \(gate.pendingArmCount) arms parked — a stacked loop, not a single collapsed one")

        gate.release()
        try await gate.waitForArm(timeout: Self.stallTolerantTimeout)
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
            try await gate.waitForArm(timeout: Self.stallTolerantTimeout)
            gate.release()
            // Proves the tick already fired: the loop only re-arms after
            // `onTick()` runs.
            try await gate.waitForArm(timeout: Self.stallTolerantTimeout)
            try #require(tickCount == 1)
            // Deliberately no `stop()` — the instance is released here, which
            // is the whole point. The loop captures `interval` and `onTick`
            // by value and never touches `self`, so nothing about the task
            // itself notices the owner is gone; only `deinit` does.
        }

        // Not `gate.release()` + a `tickCount` read: resuming a continuation
        // only re-enqueues the (leaked) loop's body onto the main actor —
        // with no suspension point before the assertion, that enqueued job
        // would not have run `onTick()` yet regardless of whether `deinit`
        // cancelled the task or not, so the read would pass unchanged either
        // way. `pendingArmCount` needs no suspension point: ARC releases
        // `heartbeat` synchronously at the end of the `do` block above (the
        // `withExtendedLifetime` defer guarantees no earlier), `deinit`
        // calls `task?.cancel()` synchronously, and `Task.cancel()` invokes
        // the gate's `onCancel` handler synchronously too — so the arm is
        // already retired, or not, before this line ever runs.
        #expect(gate.pendingArmCount == 0, "A released heartbeat must retire its pending sleep, not leave it parked forever")

        // Drains the arm if the check above just failed (a leaked arm would
        // otherwise strand a `CheckedContinuation` past this test's lifetime).
        gate.releaseAll()
    }
}
