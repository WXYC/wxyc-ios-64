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
        harness.reset()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let startedSessionID = try #require(harness.mockAnalytics.startedEvents.last?.sessionID,
            "play() should capture a session id")

        harness.simulateStall()
        await harness.waitForAsync()

        let stalledEvents = harness.mockAnalytics.stoppedEvents.filter { $0.reason == "stalled" }
        #expect(stalledEvents.last?.sessionID == startedSessionID,
               "A stall mid-listen must not mint a new session id")

        try harness.controller.toggle(reason: .testToggle)

        #expect(harness.mockAnalytics.stoppedEvents.last?.sessionID == startedSessionID,
               "The genuine stop that ends the listen should still report the same session id")
    }

    @Test("A genuine user stop followed by play mints a new session id", arguments: PlayerControllerTestCase.allCases)
    func userStopThenPlayMintsNewSessionID(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.reset()

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
    #endif
}
