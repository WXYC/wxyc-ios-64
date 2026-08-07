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
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import PlaybackCore

@Suite("PlaybackHeartbeat Component Tests")
@MainActor
struct PlaybackHeartbeatComponentTests {

    /// Short enough that several ticks happen well within a test's time budget.
    private static let testInterval: Duration = .milliseconds(30)

    @Test("start() ticks repeatedly at the configured interval")
    func startTicksRepeatedly() async throws {
        var tickCount = 0
        let heartbeat = PlaybackHeartbeat(interval: Self.testInterval) {
            tickCount += 1
        }

        heartbeat.start()
        await waitUntil({ tickCount >= 3 }, timeout: .seconds(2))

        #expect(tickCount >= 3)

        heartbeat.stop()
    }

    @Test("stop() cancels the loop — no further ticks")
    func stopCancelsLoop() async throws {
        var tickCount = 0
        let heartbeat = PlaybackHeartbeat(interval: Self.testInterval) {
            tickCount += 1
        }

        heartbeat.start()
        await waitUntil({ tickCount >= 1 }, timeout: .seconds(2))
        try #require(tickCount >= 1)

        heartbeat.stop()
        let countAtStop = tickCount

        try await Task.sleep(for: .milliseconds(150))

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
        var tickCount = 0
        let heartbeat = PlaybackHeartbeat(interval: Self.testInterval) {
            tickCount += 1
        }

        // Start, then immediately restart before the first interval elapses.
        // A correct implementation cancels the first loop and begins timing
        // fresh from the second `start()`, so exactly one loop is alive.
        heartbeat.start()
        heartbeat.start()

        // The signal is the tick *rate*, not a tick at an odd offset. Both
        // `start()` calls happen within microseconds of each other, so a
        // stacked second loop would sleep the same interval from effectively
        // the same instant and tick very nearly in phase with the first — a
        // sub-interval window placed after the first tick would see nothing
        // wrong. What changes is throughput: a stacked pair delivers two
        // ticks per interval, so it reaches any given count in half the time.
        //
        // Measuring elapsed time to a tick target, rather than counting ticks
        // in a fixed window, is what keeps this off the flake list. The suite
        // runs in parallel and the main actor is contended, so a fixed window
        // can legitimately yield one tick where the arithmetic predicts five.
        // Contention can only push elapsed time *up*, and the assertion is a
        // lower bound — a loaded machine never fails it.
        await waitUntil({ tickCount >= 1 }, timeout: .seconds(5))
        try #require(tickCount >= 1)

        let target = tickCount + 4
        let start = ContinuousClock.now
        await waitUntil({ tickCount >= target }, timeout: .seconds(5))
        try #require(tickCount >= target, "The surviving loop should still be ticking")
        let elapsed = ContinuousClock.now - start

        // One loop needs four full intervals to add four ticks; a stacked
        // pair would get there in two. The threshold sits between them.
        let floor = Self.testInterval * 5 / 2
        #expect(elapsed >= floor, "Four more ticks arrived in \(elapsed) — too fast for a single loop, so start() stacked a second one")

        heartbeat.stop()
    }

    @Test("a heartbeat released without stop() stops ticking")
    func releasedHeartbeatStopsTicking() async throws {
        var tickCount = 0

        do {
            let heartbeat = PlaybackHeartbeat(interval: Self.testInterval) {
                tickCount += 1
            }
            heartbeat.start()
            await waitUntil({ tickCount >= 1 }, timeout: .seconds(2))
            try #require(tickCount >= 1)
            // Deliberately no `stop()` — the instance is released here, which
            // is the whole point. The loop captures `interval` and `onTick`
            // by value and never touches `self`, so nothing about the task
            // itself notices the owner is gone.
        }

        let countAtRelease = tickCount
        try await Task.sleep(for: Self.testInterval * 5)

        #expect(tickCount == countAtRelease, "A released heartbeat must not keep ticking forever")
    }

    // MARK: - Helpers

    /// Polls `condition` until it holds or `timeout` elapses.
    ///
    /// Sleeps between checks rather than spinning on `Task.yield()`: the
    /// thing being waited on here is a main-actor timer loop, and a yield
    /// spin on the same actor competes with it for exactly the resource it
    /// needs to make progress.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if ContinuousClock.now >= deadline {
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
