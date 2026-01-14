//
//  AnalyticsIntegrationTests.swift
//  Playback
//
//  Analytics capture and reason string tests for all PlaybackController implementations.
//  Verifies that all controllers have identical analytics behavior.
//
//  Created by Jake Bromberg on 12/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
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

// MARK: - Analytics Integration Tests

@Suite("Analytics Integration Tests")
@MainActor
struct AnalyticsIntegrationTests {

    @Test("play() calls analytics", arguments: PlayerControllerTestCase.allCases)
    func playCallsAnalytics(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.reset()
        harness.controller.play()
        #expect(harness.analyticsPlayCallCount > 0, "play() should call analytics")
    }

    @Test("toggle() to stop calls analytics with duration", arguments: PlayerControllerTestCase.allCases)
    func toggleToStopCallsAnalyticsWithDuration(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.reset()
        harness.controller.play()

        // Small delay to ensure non-zero duration
        try? await Task.sleep(for: .milliseconds(10))

        try harness.controller.toggle(reason: "test toggle")
        #expect(harness.analyticsStopCallCount > 0, "toggle() to stop should call analytics")
        #expect(harness.lastAnalyticsStopDuration != nil, "toggle() to stop should report duration")
    }

    @Test("Analytics receives play reason", arguments: PlayerControllerTestCase.allCases)
    func analyticsReceivesPlayReason(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        try harness.controller.play(reason: "user tapped play")

        #expect(harness.mockAnalytics.startedEvents.count == 1)
        #expect(harness.mockAnalytics.startedEvents.first?.reason == "user tapped play")
    }

    @Test("Analytics receives stop duration via toggle", arguments: PlayerControllerTestCase.allCases)
    func analyticsReceivesStopDurationViaToggle(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()

        // Wait a bit to accumulate duration
        try? await Task.sleep(for: .milliseconds(50))

        try harness.controller.toggle(reason: "test toggle")

        #expect(harness.mockAnalytics.stoppedEvents.count == 1)
        if let duration = harness.mockAnalytics.stoppedEvents.first?.duration {
            #expect(duration >= 0.04, "Duration should be at least 40ms")
        } else {
            Issue.record("Expected stop duration to be recorded")
        }
    }

    @Test("toggle() to stop reports analytics stopped event", arguments: PlayerControllerTestCase.allCases)
    func toggleToStopReportsAnalyticsStoppedEvent(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        try harness.controller.toggle(reason: "test toggle")

        #expect(harness.mockAnalytics.stoppedEvents.count == 1, "toggle() to stop should report analytics stopped event")
    }

    @Test("toggle() to stop reports nil reason (user-initiated)", arguments: PlayerControllerTestCase.allCases)
    func toggleToStopReportsNilReason(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.mockAnalytics.reset()

        try harness.controller.toggle(reason: "test toggle")

        #expect(harness.mockAnalytics.stoppedEvents.count == 1)
        #expect(harness.mockAnalytics.stoppedEvents.first?.reason == nil,
               "toggle() to stop should report nil reason for user-initiated stops")
    }

    @Test("stop() alone does NOT capture analytics", arguments: PlayerControllerTestCase.allCases)
    func stopAloneDoesNotCaptureAnalytics(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.mockAnalytics.reset()

        harness.controller.stop()

        #expect(harness.mockAnalytics.stoppedEvents.isEmpty,
               "stop() alone should NOT capture analytics - call sites must capture before calling stop()")
    }

    @Test("play() reports exact reason string", arguments: PlayerControllerTestCase.allCases)
    func playReportsExactReasonString(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        let expectedReason = "CarPlay listen live tapped"

        try harness.controller.play(reason: expectedReason)

        #expect(harness.mockAnalytics.startedEvents.count == 1)
        #expect(harness.mockAnalytics.startedEvents.first?.reason == expectedReason,
               "play() should report the exact reason string passed in")
    }

    @Test("Multiple play reasons are captured distinctly", arguments: [
        "PlayWXYC intent",
        "ToggleWXYC intent",
        "CarPlay listen live tapped",
        "home screen play quick action",
        "remotePlayCommand",
        "remote toggle play/pause",
        "Resume after interruption ended",
        "foreground toggle"
    ])
    func multiplePlayReasonsAreCapturedDistinctly(reason: String) async throws {
        // Test with AudioPlayerController
        #if os(iOS) || os(tvOS)
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        try harness.controller.play(reason: reason)
        #expect(harness.mockAnalytics.startedEvents.first?.reason == reason,
               "AudioPlayerController should capture exact reason '\(reason)'")
        #endif

        // Test with RadioPlayerController
        let radioHarness = PlayerControllerTestHarness.make(for: .radioPlayerController)
        try radioHarness.controller.play(reason: reason)
        #expect(radioHarness.mockAnalytics.startedEvents.first?.reason == reason,
               "RadioPlayerController should capture exact reason '\(reason)'")
    }
}

// MARK: - Analytics Reason String Tests (iOS)

#if os(iOS)
@Suite("Analytics Reason String Tests")
@MainActor
struct AnalyticsReasonStringTests {

    @Test("Interruption began reports 'interruption began' reason", arguments: PlayerControllerTestCase.allCases)
    func interruptionBeganReportsCorrectReason(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.mockAnalytics.reset()

        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.stoppedEvents.count >= 1,
               "Interruption began should capture stopped event")
        #expect(harness.mockAnalytics.stoppedEvents.first?.reason == "interruption began",
               "Interruption began should report 'interruption began' reason")
    }

    @Test("Route disconnected reports 'route disconnected' reason")
    func routeDisconnectedReportsCorrectReason() async throws {
        // Only AudioPlayerController handles route changes with analytics
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.mockAnalytics.reset()

        // Simulate route change (old device unavailable = headphones unplugged)
        harness.notificationCenter.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            ]
        )
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.stoppedEvents.count >= 1,
               "Route disconnected should capture stopped event")
        #expect(harness.mockAnalytics.stoppedEvents.first?.reason == "route disconnected",
               "Route disconnected should report 'route disconnected' reason")
    }

    @Test("Stall reports 'stalled' reason")
    func stallReportsCorrectReason() async throws {
        // Test with RadioPlayerController which has stall handling via notification
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.mockAnalytics.reset()

        harness.simulateStall()
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.stoppedEvents.count >= 1,
               "Stall should capture stopped event")
        #expect(harness.mockAnalytics.stoppedEvents.first?.reason == "stalled",
               "Stall should report 'stalled' reason")
    }
}
#endif
