//
//  StallRecoverySabotageTests.swift
//  Playback
//
//  Regression tests for stall-recovery bugs where the reconnect loop sabotaged
//  itself, falsely credited the user's manual recovery, or both. See the bug
//  report in the agent task that drove these tests for the full log narrative.
//
//  Created by Jake Bromberg on 05/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
import Core
import Analytics
import AnalyticsTesting
@testable import Playback
@testable import PlaybackCore

#if !os(watchOS)

/// Tests that drove fixes for three stall-recovery bugs in `AudioPlayerController`:
///
/// - **Bug B**: `play(reason:)` failed to cancel a pending `reconnectTask`.
///   An orphaned reconnect attempt could wake up later and emit a
///   `StallRecoveryEvent`, falsely crediting auto-recovery for the user's
///   manual play.
@Suite("Stall Recovery Sabotage Tests")
@MainActor
struct StallRecoverySabotageTests {

    // MARK: - Test Fixture

    /// Bundle of objects needed for these tests. Built without the parameterized
    /// harness because `audioPlayerController` isn't a `PlayerControllerTestCase`
    /// on macOS (where `swift test` runs), and these tests are
    /// AudioPlayerController-specific regressions.
    private struct Fixture {
        let controller: AudioPlayerController
        let mockPlayer: MockAudioPlayer
        let mockAnalytics: MockStructuredAnalytics
    }

    private static func makeFixture(
        backoff: ExponentialBackoff = .default
    ) -> Fixture {
        let mockPlayer = MockAudioPlayer(url: URL(string: "https://example.com/stream")!)
        let mockAnalytics = MockStructuredAnalytics()
        let notificationCenter = NotificationCenter()

        #if os(iOS) || os(tvOS)
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: notificationCenter,
            analytics: mockAnalytics,
            backoffTimer: backoff
        )
        #else
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: notificationCenter,
            analytics: mockAnalytics,
            backoffTimer: backoff
        )
        #endif

        return Fixture(controller: controller, mockPlayer: mockPlayer, mockAnalytics: mockAnalytics)
    }

    /// Drains queued MainActor work so the controller's stateStream observer
    /// catches up with the mock player.
    private static func waitForAsync() async {
        for _ in 0..<32 {
            await Task.yield()
        }
    }

    /// Brings the controller to a playing state from a clean fixture.
    private static func startPlaying(_ fixture: Fixture) async {
        fixture.controller.play(reason: .test)
        fixture.mockPlayer.simulateStateChange(to: .playing)
        await waitForAsync()
    }

    /// Triggers a stall and waits for the reconnect task to be scheduled and
    /// the controller's mirrored state to reflect the stall.
    private static func triggerStall(_ fixture: Fixture) async {
        fixture.mockPlayer.shouldAutoUpdateState = false
        fixture.mockPlayer.simulateStall()

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline,
              fixture.controller.reconnectTask == nil || fixture.controller.isPlaying {
            await Task.yield()
        }
    }

    // MARK: - Bug B: play(reason:) cancels pending reconnectTask

    @Test("play(reason:) cancels pending reconnect task")
    func playCancelsPendingReconnectTask() async {
        // Use a backoff with a long-enough wait that the reconnect task is
        // guaranteed to still be sleeping when we call play().
        let slowBackoff = ExponentialBackoff(initialWaitTime: 5.0, maximumWaitTime: 5.0, maximumAttempts: 5)
        let fixture = Self.makeFixture(backoff: slowBackoff)

        await Self.startPlaying(fixture)
        await Self.triggerStall(fixture)

        let reconnectTask = fixture.controller.reconnectTask
        #expect(reconnectTask != nil, "Stall should schedule a reconnect task")

        // User presses play while the reconnect task is sleeping.
        fixture.controller.play(reason: .remotePlayCommand)

        #expect(reconnectTask?.isCancelled == true,
                "play(reason:) must cancel the pending reconnect task")
    }
}

#endif
