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

        await waitUntil({ tickCount >= 1 }, timeout: .seconds(2))
        try #require(tickCount >= 1)

        // Sleep less than a full interval past the first tick. If restarting
        // had stacked a second overlapping loop, this window would catch its
        // extra tick landing out of phase with the first loop's cadence.
        let countAfterFirstTick = tickCount
        try await Task.sleep(for: .milliseconds(15))
        #expect(tickCount == countAfterFirstTick, "A stacked second loop would tick out of phase with the first")

        heartbeat.stop()
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if ContinuousClock.now >= deadline {
                return
            }
            await Task.yield()
        }
    }
}
