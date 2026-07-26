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

    /// Short enough that several ticks happen well within a test's time
    /// budget; the production default is 60s (see
    /// `AudioPlayerController.heartbeatInterval`).
    private static let testInterval: Duration = .milliseconds(30)

    // MARK: - Kill-robust duration reconstruction

    @Test(
        "A never-paused session emits reconstructable heartbeats sharing the play event's session id",
        arguments: PlayerControllerTestCase.allCases
    )
    func neverPausedSessionEmitsReconstructableHeartbeats(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase, heartbeatInterval: Self.testInterval)
        harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let startedSessionID = try #require(
            harness.mockAnalytics.startedEvents.last?.sessionID,
            "play() should capture a session id"
        )

        // Advance past several heartbeat intervals with NO pause — modeling
        // the app being killed mid-listen (swiped away, OS-terminated,
        // crashed) so the session never reaches a clean stop.
        await harness.waitUntil({ harness.heartbeatEvents.count >= 3 }, timeout: .seconds(2))

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
    }

    @Test(
        "Heartbeats fire at the fixed cadence while playing: cumulative_seconds strictly increases tick over tick",
        arguments: PlayerControllerTestCase.allCases
    )
    func heartbeatsFireAtFixedCadence(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase, heartbeatInterval: Self.testInterval)
        harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        await harness.waitUntil({ harness.heartbeatEvents.count >= 3 }, timeout: .seconds(2))

        let heartbeats = harness.heartbeatEvents
        try #require(heartbeats.count >= 3)

        // Each successive heartbeat reflects strictly more elapsed playing
        // time than the last — proof the cadence is actually ticking forward
        // against the same monotonic timer, not just re-emitting a frozen value.
        for index in 1..<3 {
            #expect(heartbeats[index].cumulativeSeconds > heartbeats[index - 1].cumulativeSeconds,
                   "Heartbeat \(index) should report more elapsed time than heartbeat \(index - 1)")
        }

        harness.controller.stop()
    }

    // MARK: - Prompt cancellation (no leaked timer)

    @Test(
        "Heartbeat stops promptly on a genuine stop — no further heartbeats leak through",
        arguments: PlayerControllerTestCase.allCases
    )
    func heartbeatStopsOnGenuineStop(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase, heartbeatInterval: Self.testInterval)
        harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        await harness.waitUntil({ harness.heartbeatEvents.count >= 1 }, timeout: .seconds(2))
        try #require(harness.heartbeatEvents.count >= 1)

        try harness.controller.toggle(reason: .testToggle)
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        let countAtStop = harness.heartbeatEvents.count

        // Sleep past several more intervals; a leaked timer would keep
        // ticking and grow the count.
        try await Task.sleep(for: .milliseconds(150))

        #expect(harness.heartbeatEvents.count == countAtStop,
               "No heartbeat should fire after a genuine stop (expected \(countAtStop), got \(harness.heartbeatEvents.count))")
    }

    @Test(
        "Heartbeat stops promptly on a stall — no further heartbeats until a genuine recovery",
        arguments: PlayerControllerTestCase.allCases
    )
    func heartbeatStopsOnStall(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase, heartbeatInterval: Self.testInterval)
        harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        await harness.waitUntil({ harness.heartbeatEvents.count >= 1 }, timeout: .seconds(2))
        try #require(harness.heartbeatEvents.count >= 1)

        harness.simulateStall()
        await harness.waitForAsync()

        let countAtStall = harness.heartbeatEvents.count

        try await Task.sleep(for: .milliseconds(150))

        #expect(harness.heartbeatEvents.count == countAtStall,
               "No heartbeat should fire while stalled (expected \(countAtStall), got \(harness.heartbeatEvents.count))")

        harness.controller.stop()
    }

    #if os(iOS)
    @Test("Heartbeat stops promptly on an interruption — no further heartbeats until auto-resume")
    func heartbeatStopsOnInterruption() async throws {
        // Interruption analytics/session behavior is only exercised through
        // AudioPlayerController's NotificationCenter-driven path in this
        // harness (mirrors SessionIdentityTests.interruptionAutoResumePreservesSessionID).
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController, heartbeatInterval: Self.testInterval)
        harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        await harness.waitUntil({ harness.heartbeatEvents.count >= 1 }, timeout: .seconds(2))
        try #require(harness.heartbeatEvents.count >= 1)

        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        let countAtInterruption = harness.heartbeatEvents.count

        try await Task.sleep(for: .milliseconds(150))

        #expect(harness.heartbeatEvents.count == countAtInterruption,
               "No heartbeat should fire while interrupted (expected \(countAtInterruption), got \(harness.heartbeatEvents.count))")

        harness.controller.stop()
    }
    #endif
}
