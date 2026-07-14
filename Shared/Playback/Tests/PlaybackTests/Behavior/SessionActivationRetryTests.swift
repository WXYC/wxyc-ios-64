//
//  SessionActivationRetryTests.swift
//  Playback
//
//  Behavior tests for the audio-session (re)activation retry/deferral path that
//  guards against `com.apple.coreaudio.avfaudio` `CannotInterruptOthers`
//  ('!int') failures stranding playback on iOS 18. Field tracing (#509 / #514)
//  showed the session failing to activate around foreground/background
//  transitions and rapid play/pause, with `Audio session activated` never
//  firing. These tests pin down the bounded-retry and interruption-ended
//  behavior that keeps a transient "can't interrupt other audio" state from
//  leaving playback dead.
//
//  Created by Jake Bromberg on 07/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
@testable import Playback
@testable import PlaybackCore

#if os(iOS)

/// Reproduces the `'!int'` `CannotInterruptOthers` NSError observed in the
/// field so the retry path can be exercised deterministically.
@MainActor
private func cannotInterruptOthersError() -> NSError {
    NSError(
        domain: "com.apple.coreaudio.avfaudio",
        code: Int(AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue)
    )
}

@Suite("Session Activation Retry Tests")
@MainActor
struct SessionActivationRetryTests {

    // MARK: - Bounded retry recovers a transient CannotInterruptOthers

    @Test("A transient CannotInterruptOthers failure is retried until the session activates")
    func transientFailureRetriedUntilActivated() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Model a transient state: the first activation fails with '!int', then
        // subsequent activations succeed.
        harness.mockSession.setActiveError = cannotInterruptOthersError()
        harness.mockSession.failSetActiveCount = 1

        harness.controller.play()

        // The initial synchronous activation failed; the controller should have
        // scheduled a deferred retry that eventually activates the session. Wait
        // for a second `setActive` call (the retry) to land.
        await harness.waitUntil({ harness.mockSession.setActiveCallCount >= 2 },
                                timeout: .seconds(2))

        #expect(harness.mockSession.setActiveCallCount >= 2,
               "Controller should retry activation after a transient CannotInterruptOthers failure")
        #expect(harness.mockSession.lastActiveState == true,
               "Session should eventually activate once the transient state clears")
    }

    @Test("Once the retry activates the session, playback proceeds")
    func retrySuccessResumesPlayback() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.mockSession.setActiveError = cannotInterruptOthersError()
        harness.mockSession.failSetActiveCount = 1

        let playsBefore = harness.playCallCount
        harness.controller.play()

        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: .seconds(2))

        #expect(harness.playCallCount > playsBefore,
               "Deferred activation success should drive the player to start playing")
    }

    // MARK: - Retry is bounded (does not busy-loop forever)

    @Test("Retries are bounded when CannotInterruptOthers never clears")
    func retriesAreBounded() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Never clears — every activation throws '!int'.
        harness.mockSession.setActiveError = cannotInterruptOthersError()
        harness.mockSession.shouldThrowOnSetActive = true

        harness.controller.play()

        // Let the retry loop run well past its bounded budget
        // (initial attempt + maxSessionActivationRetries × retryDelay).
        try? await Task.sleep(for: .milliseconds(1500))
        let attemptsAfterExhaustion = harness.mockSession.setActiveCallCount

        // The retries must have stopped by now — a further wait adds no calls.
        try? await Task.sleep(for: .milliseconds(600))
        #expect(harness.mockSession.setActiveCallCount == attemptsAfterExhaustion,
               "Activation retries must be bounded and stop after the budget is exhausted")
        // A handful of bounded attempts, never an unbounded busy-loop.
        #expect(attemptsAfterExhaustion <= 8,
               "Activation attempts should stay within the bounded budget, got \(attemptsAfterExhaustion)")
        #expect(!harness.controller.isPlaying,
               "Playback should not report playing when the session never activated")
    }

    // MARK: - Respect interruption-ended rather than busy-retrying

    @Test("Interruption-ended reactivates a pending session instead of only busy-retrying")
    func interruptionEndedReactivatesPendingSession() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Activation keeps failing (as during a live interruption) until the
        // system signals the interruption ended.
        harness.mockSession.setActiveError = cannotInterruptOthersError()
        harness.mockSession.shouldThrowOnSetActive = true

        harness.controller.play()
        await harness.waitForAsync()

        let attemptsBeforeEnd = harness.mockSession.setActiveCallCount

        // The interruption ends: activation is now permitted again.
        harness.mockSession.shouldThrowOnSetActive = false
        harness.postInterruptionEnded(shouldResume: true)

        await harness.waitUntil({ harness.mockSession.lastActiveState == true && harness.mockSession.setActiveCallCount > attemptsBeforeEnd },
                                timeout: .seconds(2))

        #expect(harness.mockSession.setActiveCallCount > attemptsBeforeEnd,
               "Interruption-ended should trigger a fresh activation attempt")
        #expect(harness.mockSession.lastActiveState == true,
               "Session should activate once the interruption ends and activation is permitted")
    }

    // MARK: - Non-interruption failures do not schedule the interruption retry

    @Test("A non-CannotInterruptOthers activation failure does not spin up unbounded retries")
    func genericFailureDoesNotRetry() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // A generic activation failure (not '!int') should keep the existing
        // fail-fast behavior — no deferred interruption retry.
        harness.mockSession.shouldThrowOnSetActive = true

        harness.controller.play()
        await harness.waitForAsync()

        let attemptsAfterPlay = harness.mockSession.setActiveCallCount
        try? await Task.sleep(for: .milliseconds(400))

        #expect(harness.mockSession.setActiveCallCount == attemptsAfterPlay,
               "Generic activation failures should not trigger the CannotInterruptOthers retry loop")
        #expect(!harness.controller.isPlaying)
    }

    // MARK: - Stop cancels a pending retry

    @Test("Stopping cancels a pending session-activation retry")
    func stopCancelsPendingRetry() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.mockSession.setActiveError = cannotInterruptOthersError()
        harness.mockSession.shouldThrowOnSetActive = true

        harness.controller.play()
        await harness.waitForAsync()

        harness.controller.stop()
        let attemptsAtStop = harness.mockSession.setActiveCallCount

        // After stop, deactivation may be attempted, but no further activation
        // retries should fire.
        try? await Task.sleep(for: .milliseconds(500))
        let activationsAfterStop = harness.mockSession.setActiveCallCount - attemptsAtStop
        #expect(activationsAfterStop <= 0 || harness.mockSession.lastActiveState == false,
               "Stopping should cancel the pending activation retry")
    }
}

#endif
