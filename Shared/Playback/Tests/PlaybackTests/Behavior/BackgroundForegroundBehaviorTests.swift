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
import Core
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule

// MARK: - Background/Foreground Behavior Tests (iOS)

#if os(iOS)
/// Lifecycle behavior every `PlaybackController` owes, exercised through the
/// `PlaybackController` requirements themselves rather than by posting
/// `UIApplication` notifications.
///
/// The protocol methods are the only door either controller has: both are
/// driven from SwiftUI's `scenePhase` (`WXYCApp.swift`), and neither observes
/// `UIApplication.didEnterBackgroundNotification`. Posting the notification —
/// which these tests used to do — reached `RadioPlayerController` only, and
/// stopped reaching anything once its observers came out in #788, at which
/// point every assertion here held vacuously without a single test failing.
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
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        await harness.waitForAsync()

        // Should NOT have stopped
        #expect(harness.stopCallCount == stopCountBefore,
               "Background while playing should not stop")
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background while playing must not touch the session — audio would stop")
    }

    @Test("Background without ever having played leaves the session alone", arguments: PlayerControllerTestCase.allCases)
    func backgroundWhileNotPlayingIsHandled(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)

        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying)
        // Deactivating a session this app never activated fans a
        // `.notifyOthersOnDeactivation` resume out to every other audio app
        // over a session it never took. Both controllers guard on having
        // activated first.
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Backgrounding must not hand back a session this controller never activated")
    }

    @Test("Foreground while playing reactivates", arguments: PlayerControllerTestCase.allCases)
    func foregroundWhilePlayingReactivates(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        harness.controller.handleAppDidEnterBackground()
        await harness.waitForAsync()

        let stopCountBefore = harness.stopCallCount
        harness.mockSession.reset()
        harness.controller.handleAppWillEnterForeground()
        await harness.waitForAsync()

        #expect(harness.controller.isPlaying,
               "Foreground while playing must leave playback running")
        #expect(harness.stopCallCount == stopCountBefore,
               "Foreground while playing must not stop the player")
        #expect(harness.sessionActivated,
               "Foreground while playing re-affirms the session")
    }

    @Test("Foreground while not playing does not start playback", arguments: PlayerControllerTestCase.allCases)
    func foregroundWhileNotPlayingDoesNotStartPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)

        let playCountBefore = harness.playCallCount
        let stopCountBefore = harness.stopCallCount
        harness.controller.handleAppWillEnterForeground()
        await harness.waitForAsync()

        // Should NOT have started playback automatically — and, with no
        // intent on record, should not have stopped anything either.
        #expect(!harness.controller.isPlaying,
               "Foreground while not playing should not start playback")
        #expect(harness.playCallCount == playCountBefore,
               "Foreground while not playing should not start playback")
        #expect(harness.stopCallCount == stopCountBefore,
               "Foreground with no playback intended has nothing to reconcile")
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

        // stop() should have deactivated session (playbackIntended is now false).
        // The deactivation is deferred off the caller's turn — see
        // PauseResponsivenessTests — so it is awaited rather than read inline.
        await harness.waitUntil({ harness.mockSession.lastActiveState == false }, timeout: .seconds(5))
        #expect(harness.mockSession.setActiveCallCount >= 1,
               "stop() should deactivate session")
        #expect(harness.mockSession.lastActiveState == false,
               "Session should be set to inactive")

        // Let the handback fully settle before re-using the mock: the mock
        // records the call while the controller still considers the handback
        // in flight, and a backgrounding that lands in that gap queues a
        // deferred re-drive that would land after this test's last assertion.
        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: .seconds(5))

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

        // The handback the stop() above scheduled hasn't run yet — everything
        // so far happened in one main-actor turn, so at this point it hasn't
        // even started. Settle it before asserting, so a regressed staleness
        // check that wrongly tears the session down can't land after the
        // test's last statement and pass unobserved.
        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: .seconds(5))
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background after stop-then-play should NOT deactivate")
    }

    @Test("stop() clears playbackIntended and deactivates promptly")
    func stopClearsPlaybackIntendedAndDeactivates() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        try harness.controller.play(reason: .test)
        harness.mockSession.reset()

        harness.controller.stop()

        // stop() itself should deactivate — off its own turn, but with no other
        // event needed to drive it. See PauseResponsivenessTests.
        await harness.waitUntil({ harness.mockSession.lastActiveState == false }, timeout: .seconds(5))
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

// MARK: - RadioPlayerController Background/Foreground Specific Tests

/// Characterization tests pinning `RadioPlayerController`'s `#if os(iOS)`
/// lifecycle block (#777, #788).
///
/// That block has no caller in the shipping app — watchOS is the only platform
/// that instantiates the controller, and watchOS compiles the block out — so
/// nothing else in the suite exercises it. These tests are therefore the only
/// thing that will notice if the handback is deferred or dropped, if the
/// intent-based guard regresses to actual-state, or if the foreground half
/// goes back to stopping a play that is merely still buffering.
///
/// The synchronous shape is the intended one, not a lag behind #774: that PR
/// defers `AudioPlayerController.stop()`'s handback but keeps the
/// *backgrounding* handback on the caller's turn, which is what this is. See
/// the comment on `handleApplicationDidEnterBackground()`.
@Suite("RadioPlayerController Background/Foreground Behavior Tests")
@MainActor
struct RadioPlayerControllerBackgroundBehaviorTests {

    @Test("Backgrounding after a stop hands the session back on the caller's turn")
    func backgroundAfterStopDeactivatesSynchronously() throws {
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)

        // `play()` activates; `stop()` clears intent but leaves the session
        // active — this controller's `tearDown(reason:)` touches the session not
        // at all — so backgrounding is what hands it back. This is the whole
        // negative half of the intent guard: if `tearDown(reason:)` ever stopped
        // clearing `playbackIntended`, every handback would be swallowed.
        try harness.controller.play(reason: .test)
        harness.controller.tearDown(reason: .test)

        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()

        // This test body is deliberately non-`async`: there is no suspension
        // point for a deferred handback to run in, so the count being 1 here
        // is a structural assertion that the call happened inline. Wrapping
        // the handback in a `Task` leaves it at 0.
        #expect(harness.mockSession.setActiveCallCount == 1,
               "Backgrounding while stopped should hand the session back")
        #expect(harness.mockSession.lastActiveState == false,
               "The handback should deactivate, not activate")
        #expect(harness.mockSession.lastActiveOptions == .notifyOthersOnDeactivation,
               "Other audio apps must be told they can resume")
    }

    @Test("Backgrounding a session this controller never activated leaves it alone")
    func backgroundWithoutActivationDoesNotDeactivate() {
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)
        #expect(!harness.controller.isPlaying)

        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()

        #expect(harness.mockSession.setActiveCallCount == 0,
               "Deactivating a session never activated fans a resume out to every other audio app")
    }

    /// One claim, two observable states: intent suppresses the handback
    /// whether or not the player has started rendering audio yet.
    ///
    /// `playbackStarted: false` is the buffering window a real `AVPlayer` sits
    /// in between `play()`'s `setActive(true, …)` and audio actually playing —
    /// `isPlaying` is false there, which is exactly the case the pre-#788
    /// `isPlaying` guard missed.
    @Test(
        "Backgrounding with playback intended leaves the session alone",
        arguments: [true, false]
    )
    func backgroundWithPlaybackIntendedDoesNotDeactivate(playbackStarted: Bool) async throws {
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)
        harness.mockPlayer.shouldAutoUpdateState = playbackStarted

        try harness.controller.play(reason: .test)
        if playbackStarted {
            harness.simulatePlaybackStarted()
            await harness.waitForAsync()
        }
        #expect(harness.controller.isPlaying == playbackStarted)

        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()

        #expect(harness.mockSession.setActiveCallCount == 0,
               "Backgrounding with a play intended must not tear down the session that play activated")
    }

    @Test("Foregrounding mid-buffer keeps the pending play alive")
    func foregroundWhileBufferingKeepsPendingPlayAlive() async throws {
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)
        harness.mockPlayer.shouldAutoUpdateState = false

        try harness.controller.play(reason: .test)
        harness.controller.handleAppDidEnterBackground()

        let stopsBefore = harness.stopCallCount
        let stopEventsBefore = harness.analyticsStopCallCount
        harness.controller.handleAppWillEnterForeground()
        await harness.waitForAsync()

        // The background half already skips the handback while buffering. If
        // the foreground half still guards on `isPlaying`, it stops the very
        // play the background half just protected — same user-visible outcome,
        // one transition later (#788).
        #expect(harness.stopCallCount == stopsBefore,
               "Foregrounding mid-buffer must not stop the pending play")
        #expect(harness.analyticsStopCallCount == stopEventsBefore,
               "Foregrounding mid-buffer must not emit a stopped event")
    }

    @Test("Foregrounding while stranded re-drives the play")
    func foregroundWhileStrandedRedrivesPlay() async throws {
        // `maximumAttempts: 0` exhausts on the first stall, which is what
        // strands the controller: intent is still on record, but the player
        // is idle and no reconnect is in flight.
        let harness = PlayerControllerTestHarness.make(
            for: .radioPlayerController,
            backoffTimer: ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 0)
        )

        try harness.controller.play(reason: .test)
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.simulateStall()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        harness.controller.handleAppDidEnterBackground()
        let playsBefore = harness.playCallCount
        harness.controller.handleAppWillEnterForeground()
        await harness.waitForAsync()

        #expect(harness.playCallCount > playsBefore,
               "A stranded stream is what foregrounding is for — re-drive the play")
        #expect(harness.lastAnalyticsPlayReason == PlaybackReason.resumeAfterForeground.rawValue,
               "The re-drive should attribute itself to the foreground transition")
    }
}
#endif
