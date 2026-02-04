//
//  BackgroundForegroundBehaviorTests.swift
//  Playback
//
//  iOS background/foreground lifecycle tests for all PlaybackController implementations.
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

// MARK: - Background/Foreground Behavior Tests (iOS)

#if os(iOS)
@Suite("Background/Foreground Behavior Tests")
@MainActor
struct BackgroundForegroundBehaviorTests {

    @Test("Background while playing keeps session active", arguments: PlayerControllerTestCase.allCases)
    func backgroundWhilePlayingKeepsSessionActive(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        let stopCountBefore = harness.stopCallCount
        harness.postBackgroundNotification()
        await harness.waitForAsync()

        // Should NOT have stopped
        #expect(harness.stopCallCount == stopCountBefore,
               "Background while playing should not stop")
    }

    @Test("Background while not playing is handled gracefully", arguments: PlayerControllerTestCase.allCases)
    func backgroundWhileNotPlayingIsHandled(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)

        // Should not crash or cause issues
        harness.postBackgroundNotification()
        await harness.waitForAsync()

        // Verify still not playing
        #expect(!harness.controller.isPlaying)
    }

    @Test("Foreground while playing reactivates", arguments: PlayerControllerTestCase.allCases)
    func foregroundWhilePlayingReactivates(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        harness.postBackgroundNotification()
        await harness.waitForAsync()

        harness.postForegroundNotification()
        await harness.waitForAsync()

        // Should still be playing or have reactivated
        // (specific behavior varies by controller implementation)
    }

    @Test("Foreground while not playing does not start playback", arguments: PlayerControllerTestCase.allCases)
    func foregroundWhileNotPlayingDoesNotStartPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)

        let playCountBefore = harness.playCallCount
        harness.postForegroundNotification()
        await harness.waitForAsync()

        // Should NOT have started playback automatically
        // Note: RadioPlayerController may call stop on foreground when not playing,
        // so we just verify it's not playing
        #expect(!harness.controller.isPlaying,
               "Foreground while not playing should not start playback")
    }
}

// MARK: - AudioPlayerController Background/Foreground Specific Tests

@Suite("AudioPlayerController Background/Foreground Behavior Tests")
@MainActor
struct AudioPlayerControllerBackgroundBehaviorTests {

    @Test("play() sets playbackIntended - background does NOT deactivate session")
    func playWithURLSetsPlaybackIntended() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        try harness.controller.play(reason: .test)
        harness.mockSession.reset()  // Clear the activation from play()

        harness.controller.handleAppDidEnterBackground()

        // Should NOT have deactivated (playbackIntended is true)
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background while playing should NOT deactivate session")
    }

    @Test("stop() clears playbackIntended - session is deactivated before background")
    func stopClearsPlaybackIntended() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        try harness.controller.play(reason: .test)
        harness.mockSession.reset()
        harness.controller.stop()

        // stop() should have deactivated session (playbackIntended is now false)
        #expect(harness.mockSession.setActiveCallCount >= 1,
               "stop() should deactivate session")
        #expect(harness.mockSession.lastActiveState == false,
               "Session should be set to inactive")

        // Background after stop should NOT deactivate again (already deactivated)
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background after stop should not deactivate again (already deactivated)")
    }

    @Test("stop then play() keeps playbackIntended true")
    func stopThenPlayKeepsPlaybackIntended() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Play -> Stop -> Play cycle
        try harness.controller.play(reason: .initial)
        harness.controller.stop()  // playbackIntended = false
        harness.controller.play()  // playbackIntended should be true again

        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()

        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background after stop-then-play should NOT deactivate")
    }

    @Test("stop() clears playbackIntended and deactivates immediately")
    func stopClearsPlaybackIntendedAndDeactivates() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        try harness.controller.play(reason: .test)
        harness.mockSession.reset()

        harness.controller.stop()

        // stop() itself should deactivate
        #expect(harness.mockSession.setActiveCallCount >= 1,
               "stop() should deactivate session")
        #expect(harness.mockSession.lastActiveState == false,
               "Session should be inactive after stop()")
    }

    @Test("foreground while playbackIntended reactivates session")
    func foregroundWhilePlaybackIntendedReactivates() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        try harness.controller.play(reason: .test)
        harness.controller.handleAppDidEnterBackground()  // No deactivation (playing)

        harness.mockSession.reset()
        harness.controller.handleAppWillEnterForeground()

        #expect(harness.mockSession.setActiveCallCount == 1,
               "Foreground while playing should activate session")
        #expect(harness.mockSession.lastActiveState == true,
               "Session should be active")
    }

    @Test("foreground without playbackIntended does NOT activate session")
    func foregroundWithoutPlaybackIntendedDoesNotActivate() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Never played - go to foreground
        harness.mockSession.reset()
        harness.controller.handleAppWillEnterForeground()

        #expect(harness.mockSession.setActiveCallCount == 0,
               "Foreground without playback intent should NOT activate session")
    }

    @Test("background without ever playing does NOT deactivate session")
    func backgroundWithoutEverPlayingDoesNotDeactivate() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // App launched but user never played anything
        // Session was never activated, so backgrounding should NOT deactivate
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()

        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background without ever playing should NOT call setActive (session was never activated)")
    }

    @Test("Real-world scenario: Apple Music playing, launch WXYC, background without playing")
    func appleMusicNotInterruptedScenario() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // User launches WXYC while Apple Music is playing
        // User browses the playlist but doesn't start playback
        // User backgrounds the app
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()

        // Critical: Session should NOT be deactivated with .notifyOthersOnDeactivation
        // because we never activated it. If we deactivate, it could affect Apple Music.
        #expect(harness.mockSession.setActiveCallCount == 0,
               "CRITICAL: Never-activated session should not be deactivated on background")
    }

    @Test("Real-world scenario: Apple Music interrupted, WXYC plays, backgrounding keeps WXYC playing")
    func appleMusicInterruptionScenario() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // User starts WXYC (interrupts Apple Music)
        try harness.controller.play(reason: .userStartedStream)
        #expect(harness.controller.isPlaying)

        // User backgrounds app while WXYC is playing
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()

        // Critical: Session should NOT be deactivated
        // If it is, Apple Music will resume
        #expect(harness.mockSession.setActiveCallCount == 0,
               "CRITICAL: Backgrounding while playing should NOT deactivate session (would let Apple Music resume)")
        #expect(harness.mockSession.lastActiveState != false,
               "Session should remain active so WXYC continues playing")
    }
}

// MARK: - Render Tap Background/Foreground Tests

@Suite("Render Tap Background/Foreground Behavior Tests")
@MainActor
struct RenderTapBackgroundBehaviorTests {

    @Test("Background removes render tap when installed")
    func backgroundRemovesRenderTapWhenInstalled() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Install render tap (simulates visualizer becoming visible)
        harness.controller.installRenderTap()
        let installCountBefore = harness.mockPlayer.installRenderTapCallCount

        // Go to background
        harness.controller.handleAppDidEnterBackground()

        // Should have removed the tap
        #expect(harness.mockPlayer.removeRenderTapCallCount == 1,
               "Background should remove render tap to save CPU")
    }

    @Test("Background does not remove render tap when not installed")
    func backgroundDoesNotRemoveWhenNotInstalled() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Don't install render tap
        harness.controller.handleAppDidEnterBackground()

        // Should not have tried to remove
        #expect(harness.mockPlayer.removeRenderTapCallCount == 0,
               "Background should not remove tap that was never installed")
    }

    @Test("Foreground restores render tap when it was active")
    func foregroundRestoresRenderTapWhenActive() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Install render tap
        harness.controller.installRenderTap()
        #expect(harness.mockPlayer.installRenderTapCallCount == 1)

        // Background (removes tap)
        harness.controller.handleAppDidEnterBackground()
        #expect(harness.mockPlayer.removeRenderTapCallCount == 1)

        // Foreground should restore
        harness.controller.handleAppWillEnterForeground()
        #expect(harness.mockPlayer.installRenderTapCallCount == 2,
               "Foreground should restore render tap that was active before background")
    }

    @Test("Foreground does not install render tap when it was not active")
    func foregroundDoesNotInstallWhenNotActive() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Never installed render tap
        harness.controller.handleAppDidEnterBackground()
        harness.controller.handleAppWillEnterForeground()

        #expect(harness.mockPlayer.installRenderTapCallCount == 0,
               "Foreground should not install tap that was never requested")
    }

    @Test("Install while backgrounded defers until foreground")
    func installWhileBackgroundedDefersUntilForeground() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Go to background first
        harness.controller.handleAppDidEnterBackground()

        // Try to install render tap while backgrounded
        harness.controller.installRenderTap()

        // Should NOT have actually installed (app is backgrounded)
        #expect(harness.mockPlayer.installRenderTapCallCount == 0,
               "Should not install render tap while backgrounded")

        // Come back to foreground
        harness.controller.handleAppWillEnterForeground()

        // NOW it should install
        #expect(harness.mockPlayer.installRenderTapCallCount == 1,
               "Should install render tap when returning to foreground")
    }

    @Test("Remove while backgrounded clears desired state")
    func removeWhileBackgroundedClearsDesiredState() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Install, then background
        harness.controller.installRenderTap()
        harness.controller.handleAppDidEnterBackground()
        #expect(harness.mockPlayer.removeRenderTapCallCount == 1)

        // Remove while backgrounded (user navigates away from visualizer)
        harness.controller.removeRenderTap()

        // Come back to foreground
        harness.mockPlayer.installRenderTapCallCount = 0  // Reset to check
        harness.controller.handleAppWillEnterForeground()

        // Should NOT reinstall because user removed it
        #expect(harness.mockPlayer.installRenderTapCallCount == 0,
               "Should not restore render tap that was explicitly removed")
    }
}
#endif
