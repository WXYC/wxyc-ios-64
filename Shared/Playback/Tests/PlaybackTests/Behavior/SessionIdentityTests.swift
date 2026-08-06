//
//  SessionIdentityTests.swift
//  Playback
//
//  Listening-session identity tests for all PlaybackController implementations (#665).
//  Verifies the stable per-listen session_id lifecycle: shared across stalls,
//  regenerated on a genuine user stop, and preserved across the
//  interruption/route-disconnect auto-resume path.
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule

// MARK: - Session Identity Tests

@Suite("Session Identity Tests")
@MainActor
struct SessionIdentityTests {

    @Test("Play, stall, and a genuine stop share one session id", arguments: PlayerControllerTestCase.allCases)
    func playStallStopShareSessionID(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        await harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let startedSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID,
            "play() should capture a session id")

        harness.simulateStall()
        await harness.waitForAsync()

        // A stall no longer emits a "pause" event at all (#667) — a stall is
        // not a session end. Confirm that here so this test fails loudly if
        // that regresses, rather than the `stoppedEvents` filter below
        // silently finding nothing.
        #expect(harness.mockAnalytics.stoppedEvents.isEmpty,
               "A stall must not emit a 'pause' event (#667)")

        // Bring playback back to a confirmed-playing state before stopping.
        // RadioPlayerController's `isPlaying` is a direct passthrough to the
        // underlying player, which `simulateStall()` (correctly, matching
        // production `RadioPlayer` behaviour) drives to `false`. Toggling
        // immediately after a stall would therefore hit `play()`, not
        // `stop()`, making this a no-op rather than a genuine stop.
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        try harness.controller.toggle(reason: .testToggle)

        #expect(harness.mockAnalytics.stoppedEvents.count == 1,
               "The genuine stop should be the only 'pause' event in this listen")
        #expect(harness.mockAnalytics.stoppedEvents.last?.sessionID == startedSessionID,
               "The genuine stop that ends the listen should still report the same session id")
    }

    @Test("A genuine user stop followed by play mints a new session id", arguments: PlayerControllerTestCase.allCases)
    func userStopThenPlayMintsNewSessionID(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        await harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let firstSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID)

        try harness.controller.toggle(reason: .testToggle)
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let secondSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID)

        #expect(secondSessionID != firstSessionID,
               "A genuine stop ends the listen, so the next play must mint a fresh session id")
    }

    #if os(iOS)
    @Test("Interruption-began then interruption-ended auto-resume preserves the session id", arguments: PlayerControllerTestCase.allCases)
    func interruptionAutoResumePreservesSessionID(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let originalSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID)

        // Interruption began stops playback as a prelude to an imminent
        // auto-resume, not a genuine user stop — the session must survive it.
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()

        let resumedSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID)
        #expect(resumedSessionID == originalSessionID,
               "Auto-resume after an interruption is one listen with a gap, not a new session")

        harness.controller.stop()
    }

    @Test("Route-disconnect auto-resume preserves the session id")
    func routeDisconnectAutoResumePreservesSessionID() async throws {
        // Only AudioPlayerController handles route changes with analytics
        // (see AnalyticsIntegrationTests.routeDisconnectedReportsCorrectReason).
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let originalSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID)

        harness.postRouteChange(reason: .oldDeviceUnavailable)
        await harness.waitForAsync()

        harness.postRouteChange(reason: .newDeviceAvailable)
        await harness.waitForAsync()

        let resumedSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID)
        #expect(resumedSessionID == originalSessionID,
               "Auto-resume after a route reconnect is one listen with a gap, not a new session")

        harness.controller.stop()
    }

    @Test("Foreground auto-resume after a stranded background preserves the session id")
    func foregroundAutoResumePreservesSessionID() async throws {
        // `.resumeAfterForeground` is an AudioPlayerController-specific path
        // (RadioPlayerController's foreground handler uses `.foregroundToggle` /
        // `.foregroundNotPlaying` instead), so this is scoped to that controller,
        // mirroring `routeDisconnectAutoResumePreservesSessionID` above.
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let originalSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID)

        // AudioPlayerController's background/foreground handlers are driven
        // directly from SwiftUI's `scenePhase` (see the doc comments on
        // `handleAppDidEnterBackground`/`handleAppWillEnterForeground`), not
        // via `NotificationCenter` — unlike RadioPlayerController, it never
        // subscribes to `UIApplication` notifications. So this calls the
        // methods directly, matching `AudioPlayerControllerBackgroundBehaviorTests`
        // in BackgroundForegroundBehaviorTests.swift, rather than
        // `harness.postBackgroundNotification()` (a no-op for this controller).
        harness.controller.handleAppDidEnterBackground()
        await harness.waitForAsync()

        // Simulate the player having silently dropped while backgrounded (e.g.
        // a deferred session activation, or a terminal error) — playback
        // intent is still set, but the player itself has gone idle. This is
        // the "genuinely stranded" branch that re-drives
        // `play(reason: .resumeAfterForeground)` on foreground (see #514).
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        harness.controller.handleAppWillEnterForeground()
        await harness.waitForAsync()

        let resumedEvent = try #require(harness.mockAnalytics.startedEvents.last)
        #expect(resumedEvent.reason == PlaybackReason.resumeAfterForeground.rawValue,
               "Sanity check: this scenario should exercise the resumeAfterForeground path")
        #expect(resumedEvent.sessionID == originalSessionID,
               "Auto-resume after a stranded background is one listen with a gap, not a new session")

        harness.controller.stop()
    }
    #endif
}
