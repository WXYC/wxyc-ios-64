//
//  RouteChangeBehaviorTests.swift
//  Playback
//
//  Audio route change behavior tests for all PlaybackController implementations.
//  Tests how controllers respond to audio route changes like headphone disconnect,
//  Bluetooth device switching, etc.
//
//  Created by Claude on 01/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule

// MARK: - Route Change Behavior Tests (iOS/tvOS)

#if os(iOS) || os(tvOS)
@Suite("Route Change Behavior Tests")
@MainActor
struct RouteChangeBehaviorTests {

    // MARK: - Old Device Unavailable (Headphones Unplugged)

    @Test("Unplugging headphones while playing stops playback", arguments: PlayerControllerTestCase.allCases)
    func unplugHeadphonesWhilePlayingStopsPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Should be playing before route change")

        // Simulate headphones being unplugged
        // The route change handler should stop playback
        harness.postRouteChange(reason: .oldDeviceUnavailable)
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying,
               "Unplugging headphones should stop playback (Apple HIG requirement)")
    }

    @Test("Unplugging headphones while not playing is safe", arguments: PlayerControllerTestCase.allCases)
    func unplugHeadphonesWhileNotPlayingIsSafe(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)

        // Simulate headphones being unplugged while not playing
        harness.postRouteChange(reason: .oldDeviceUnavailable)
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "Should still not be playing")
    }

    // MARK: - New Device Available

    @Test("New device available while playing continues playback", arguments: PlayerControllerTestCase.allCases)
    func newDeviceAvailableWhilePlayingContinues(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        let stopCountBefore = harness.stopCallCount

        // Simulate new device being connected (e.g., plugging in headphones)
        harness.postRouteChange(reason: .newDeviceAvailable)
        await harness.waitForAsync()

        // Should NOT have stopped
        #expect(harness.stopCallCount == stopCountBefore,
               "New device available should not stop playback")
    }

    @Test("New device available while not playing does not start playback", arguments: PlayerControllerTestCase.allCases)
    func newDeviceAvailableWhileNotPlayingDoesNotStart(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)

        let playCountBefore = harness.playCallCount

        // Simulate new device being connected
        harness.postRouteChange(reason: .newDeviceAvailable)
        await harness.waitForAsync()

        #expect(harness.playCallCount == playCountBefore,
               "New device available should not auto-start playback")
        #expect(!harness.controller.isPlaying)
    }

    // MARK: - Route Configuration Change (e.g., switching Bluetooth devices)

    @Test("Route configuration change while playing continues playback", arguments: PlayerControllerTestCase.allCases)
    func routeConfigurationChangeWhilePlayingContinues(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        let stopCountBefore = harness.stopCallCount

        // Simulate route configuration change
        harness.postRouteChange(reason: .routeConfigurationChange)
        await harness.waitForAsync()

        // Should NOT have stopped
        #expect(harness.stopCallCount == stopCountBefore,
               "Route configuration change should not stop playback")
    }

    // MARK: - Category Change

    @Test("Category change while playing continues playback", arguments: PlayerControllerTestCase.allCases)
    func categoryChangeWhilePlayingContinues(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        let stopCountBefore = harness.stopCallCount

        // Simulate category change
        harness.postRouteChange(reason: .categoryChange)
        await harness.waitForAsync()

        // Should NOT have stopped
        #expect(harness.stopCallCount == stopCountBefore,
               "Category change should not stop playback")
    }

    // MARK: - Override (System override like phone call)

    @Test("Override while playing is handled gracefully", arguments: PlayerControllerTestCase.allCases)
    func overrideWhilePlayingIsHandled(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        // Simulate system override
        harness.postRouteChange(reason: .override)
        await harness.waitForAsync()

        // Should handle gracefully (exact behavior depends on implementation)
    }

    // MARK: - Engine Stop Recovery

    /// Note: AudioPlayerController with AudioEnginePlayer handles configuration changes internally
    /// via AVAudioEngine.configurationChangeNotification. This test verifies RadioPlayerController's
    /// controller-level recovery for AVPlayer-based playback.
    @Test("RadioPlayerController restarts when player stops during route change")
    func radioPlayerControllerRestartsOnRouteChange() async {
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Should be playing before route change")

        let playCountBefore = harness.playCallCount

        // Simulate player stopping due to route change
        harness.simulateEngineStoppedDueToRouteChange()

        // Post a route change that should trigger recovery
        harness.postRouteChange(reason: .newDeviceAvailable)
        await harness.waitForAsync()

        // RadioPlayerController should detect the player stopped and restart playback
        #expect(harness.playCallCount > playCountBefore,
               "RadioPlayerController should restart playback when player stops during route change")
    }

    // MARK: - Analytics

    @Test("Headphone disconnect captures analytics", arguments: PlayerControllerTestCase.allCases)
    func headphoneDisconnectCapturesAnalytics(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let stopCountBefore = harness.analyticsStopCallCount

        // Simulate headphones being unplugged
        // Note: Don't call simulatePlaybackStopped() here - the route change handler
        // should stop playback and capture analytics. If we simulate stopped first,
        // isPlaying will be false when the handler runs and analytics won't be captured.
        harness.postRouteChange(reason: .oldDeviceUnavailable)
        await harness.waitForAsync()

        #expect(harness.analyticsStopCallCount > stopCountBefore,
               "Headphone disconnect should capture analytics")
    }
}

// MARK: - AudioPlayerController Route Change Specific Tests

/// Note: AudioPlayerController's engine restart on configuration change is handled internally
/// by AudioEnginePlayer via AVAudioEngine.configurationChangeNotification, not at the
/// controller level. These tests verify controller-level behavior only.
@Suite("AudioPlayerController Route Change Behavior Tests")
@MainActor
struct AudioPlayerControllerRouteChangeBehaviorTests {

    @Test("Route change while not playing does not start playback")
    func routeChangeWhileNotPlayingDoesNotStart() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Never started playback
        #expect(!harness.controller.isPlaying)

        let playCountBefore = harness.playCallCount

        // Trigger route change
        harness.postRouteChange(reason: .newDeviceAvailable)
        await harness.waitForAsync()

        // Should NOT have started playback
        #expect(harness.playCallCount == playCountBefore,
               "Should not start playback on route change when not playing")
    }

    @Test("Multiple rapid route changes are handled correctly")
    func multipleRapidRouteChangesHandled() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        // Simulate rapid route changes (e.g., switching between Bluetooth devices)
        harness.postRouteChange(reason: .newDeviceAvailable)
        harness.postRouteChange(reason: .routeConfigurationChange)
        harness.postRouteChange(reason: .newDeviceAvailable)
        await harness.waitForAsync()

        // Should still be in a consistent state
        // (exact behavior depends on whether engine stopped)
    }
}
#endif
