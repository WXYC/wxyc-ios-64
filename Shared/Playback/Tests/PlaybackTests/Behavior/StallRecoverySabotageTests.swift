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
/// - **Bug A**: The 500 ms fixed-grace check after `player.play()` resolved
///   before the player had a chance to reach `.playing` on a slow cold connect
///   (~1.3–1.4 s observed). The next retry then tore down the in-flight
///   connection. The fix waits on the player's state stream up to a longer
///   timeout.
/// - **Bug C**: The "Recovery successful" branch emitted a `StallRecoveryEvent`
///   and a log line without re-checking that `stallStartTime` was still set.
///   When `play()` cleared `stallStartTime` mid-flight, the misleading log
///   line still fired. Belt-and-braces with the Bug B fix.
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

    /// Triggers a stall the way a real player would: yield `.stalled` to the
    /// state stream so the controller's mirrored `playerState` (and therefore
    /// `isPlaying`) updates, then fire the `.stall` event so `handleStall()`
    /// schedules a reconnect. `MockAudioPlayer.simulateStall()` alone only
    /// fires the event, leaving `isPlaying` reading stale from the previous
    /// state stream value.
    private static func triggerStall(_ fixture: Fixture) async {
        fixture.mockPlayer.shouldAutoUpdateState = false
        fixture.mockPlayer.simulateStateChange(to: .stalled)
        fixture.mockPlayer.simulateStall()

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline,
              fixture.controller.state != .stalled {
            await Task.yield()
        }
    }

    // MARK: - Bug A: reconnect waits on player state, not a fixed 500 ms

    @Test("reconnect waits for player to reach playing or error, not a fixed 500ms")
    func reconnectWaitsForTerminalState() async {
        // Quick first-wait so the reconnect runs promptly; the test pivots on
        // the grace-wait behavior after `player.play()`.
        let quickBackoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 10)
        let fixture = Self.makeFixture(backoff: quickBackoff)

        await Self.startPlaying(fixture)
        // Snapshot playCallCount so we can count only the reconnect's calls.
        let playCallsBeforeStall = fixture.mockPlayer.playCallCount
        await Self.triggerStall(fixture)

        // Simulate a slow cold-connect: leave the player non-playing for
        // ~1.0 s (longer than the old 500 ms grace), then yield .playing.
        // shouldAutoUpdateState is false (set by triggerStall), so the
        // reconnect's `player.play()` won't auto-flip to .playing — the
        // controller must wait for the explicit state transition.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_000))
            fixture.mockPlayer.simulateStateChange(to: .playing)
        }

        // Wait for the controller to mirror .playing (with a generous timeout).
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < deadline, !fixture.controller.isPlaying {
            try? await Task.sleep(for: .milliseconds(20))
        }

        // Under the old 500 ms fixed grace, the first attempt would have been
        // declared failed (player still not playing at the check), triggering
        // a second retry which tears down the in-flight connect. The
        // state-driven wait should resolve on the first attempt — i.e. only
        // ONE player.play() call during the recovery period.
        //
        // With 1000ms of slow-connect and a 0.01s backoff between retries,
        // the buggy 500ms grace would result in roughly 2 player.play() calls
        // by the time .playing is yielded. The fix should produce exactly 1.
        let reconnectPlayCalls = fixture.mockPlayer.playCallCount - playCallsBeforeStall
        let message = "Reconnect should issue exactly one player.play() during a 1s slow-connect; saw \(reconnectPlayCalls). More than one indicates the grace check fired before the player finished connecting."
        #expect(reconnectPlayCalls == 1, Comment(rawValue: message))
        #expect(fixture.controller.isPlaying, "Controller should report playing once state transitions")
    }

    // MARK: - Bug C: do not credit recovery when the user took over

    @Test("Recovery is not credited when user manually started playback")
    func recoveryNotCreditedWhenUserStartedPlayback() async {
        // Quick backoff so the reconnect task wakes up promptly.
        let quickBackoff = ExponentialBackoff(initialWaitTime: 0.05, maximumWaitTime: 0.05, maximumAttempts: 5)
        let fixture = Self.makeFixture(backoff: quickBackoff)

        await Self.startPlaying(fixture)
        await Self.triggerStall(fixture)

        // User takes over: manual play, then the mock player flips to .playing
        // (auto-update re-enabled to simulate the user-initiated success path).
        fixture.mockPlayer.shouldAutoUpdateState = true
        fixture.controller.play(reason: .remotePlayCommand)
        fixture.mockPlayer.simulateStateChange(to: .playing)
        await Self.waitForAsync()

        // Give any orphan reconnect task time to wake up and run its (now
        // invalid) post-grace check before we assert.
        try? await Task.sleep(for: .milliseconds(300))

        let recoveryEvents = fixture.mockAnalytics.typedEvents(ofType: StallRecoveryEvent.self)
        #expect(recoveryEvents.isEmpty,
                "User-initiated play() must not be credited as automatic recovery; got \(recoveryEvents.count) StallRecoveryEvent(s)")
    }
}

#endif
