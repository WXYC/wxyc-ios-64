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

    @Test(
        "A transient CannotInterruptOthers failure is retried until the session activates",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
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

    @Test(
        "Once the retry activates the session, playback proceeds",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
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

    @Test(
        "Retries are bounded when CannotInterruptOthers never clears",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
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

    @Test(
        "Interruption-ended reactivates a pending session instead of only busy-retrying",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
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

    @Test("A non-CannotInterruptOthers activation failure escalates recovery instead of entering the '!int' deferral loop")
    func genericFailureEscalatesInsteadOfDeferring() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // A generic activation failure (not '!int') doesn't get the deferred
        // interruption retry. Under #518 (design 6-A) it isn't fail-fast-into-
        // silence either: it escalates immediately — exactly one
        // `silent_startup` and a handoff to the reconnect ramp, which owns the
        // re-activation attempts from here.
        harness.mockSession.shouldThrowOnSetActive = true

        harness.controller.play()
        await harness.waitForAsync()

        let silentStartups = harness.streamErrorEvents.filter { $0.errorType == .silentStartup }
        #expect(silentStartups.count == 1,
               "A generic activation failure should escalate as a single silent_startup")
        #expect(!harness.controller.isPlaying)

        harness.controller.stop(reason: .test)
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

        // After stop, no further activation attempts should fire. The session
        // never activated (every `setActive(true)` threw), so `stop()` triggers
        // no deactivation call either — the count must be frozen exactly at the
        // value captured at stop. Any increase means a retry survived the stop.
        try? await Task.sleep(for: .milliseconds(500))
        let activationsAfterStop = harness.mockSession.setActiveCallCount - attemptsAtStop
        #expect(activationsAfterStop == 0,
               "Stopping should cancel the pending activation retry (no further setActive calls)")
    }

    // MARK: - Backgrounding mid-retry must not strand the pending activation

    @Test("A background/foreground cycle while a retry is pending does not strand playback")
    func backgroundingMidRetryDoesNotStrandPlayback() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Activation keeps failing with '!int' across the whole cycle.
        harness.mockSession.setActiveError = cannotInterruptOthersError()
        harness.mockSession.shouldThrowOnSetActive = true

        harness.controller.play()
        await harness.waitForAsync()

        // App backgrounds while the bounded retry is still pending, then returns
        // to the foreground while activation is *still* blocked. Stay
        // backgrounded past the retry delay (250ms) so the in-flight retry task
        // actually wakes and hits its `isForegrounded` guard — that is the exact
        // condition that leaves a stale "pending" flag behind. Foregrounding
        // then re-attempts activation (which fails again) and must arm a *fresh*
        // retry; if the stale pending state leaked through, the foreground
        // reactivation would early-out and never reschedule.
        harness.controller.handleAppDidEnterBackground()
        try? await Task.sleep(for: .milliseconds(400))
        harness.controller.handleAppWillEnterForeground()
        await harness.waitForAsync()

        // The interrupting audio finally clears; a retry must still be armed so
        // the session activates and playback starts. `lastActiveState` is set
        // even on a throwing activation, so assert on the player actually
        // starting — that only happens once a *successful* (re)activation
        // resumes the deferred playback.
        let playsBeforeClear = harness.playCallCount
        harness.mockSession.shouldThrowOnSetActive = false

        await harness.waitUntil({ harness.playCallCount > playsBeforeClear },
                                timeout: .seconds(2))

        #expect(harness.playCallCount > playsBeforeClear,
               "After a background/foreground cycle the pending retry must not be stranded: once '!int' clears, activation should succeed and playback should start")
    }

    // MARK: - Interruption-ended resume rides out a '!int' deferral

    @Test("An interruption-ended resume that hits '!int' defers and then resumes")
    func interruptionEndedResumeSurvivesDeferral() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Start cleanly playing so an interruption has prior playback to resume.
        harness.controller.play()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying,
               "Precondition: the controller should be playing before the interruption")

        // A phone call interrupts: playback stops but is flagged for resume.
        // This drives the `shouldResume && wasPlayingBeforeInterruption` == true
        // branch of the interruption-ended handler — distinct from
        // `interruptionEndedReactivatesPendingSession`, which exercises the else.
        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()

        // As the interruption ends the session still can't activate ('!int'),
        // so the resume must defer via the bounded retry, not die.
        harness.mockSession.setActiveError = cannotInterruptOthersError()
        harness.mockSession.shouldThrowOnSetActive = true

        let playsBeforeEnd = harness.playCallCount
        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()

        // The interrupting audio finally clears; the deferred resume completes.
        harness.mockSession.shouldThrowOnSetActive = false
        await harness.waitUntil({ harness.playCallCount > playsBeforeEnd },
                                timeout: .seconds(2))

        #expect(harness.playCallCount > playsBeforeEnd,
               "An interruption-ended resume that hits a transient '!int' must defer and then resume, not strand playback")
    }

    // MARK: - Foregrounding mid-buffer must not restart the stream

    @Test("Foregrounding while buffering re-affirms the session without restarting playback")
    func foregroundWhileBufferingDoesNotRestart() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Start playing cleanly, then drop into a transient buffering state
        // (not stopped): playback is still intended, the player just isn't
        // `.playing` right now.
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        harness.mockPlayer.simulateStateChange(to: .loading)
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        let playsBefore = harness.playCallCount
        let startsBefore = harness.analyticsPlayCallCount
        let setActiveBefore = harness.mockSession.setActiveCallCount

        // Background then foreground while still buffering. The stranded-recovery
        // path must NOT fire here — buffering is transient and owned by the
        // stream/reconnect machinery.
        harness.controller.handleAppDidEnterBackground()
        harness.controller.handleAppWillEnterForeground()
        await harness.waitForAsync()

        #expect(harness.playCallCount == playsBefore,
               "Foregrounding while buffering must not restart the player")
        #expect(harness.analyticsPlayCallCount == startsBefore,
               "Foregrounding while buffering must not emit a spurious playback-start event")
        #expect(harness.mockSession.setActiveCallCount > setActiveBefore,
               "Foregrounding while playback is intended should still re-affirm the audio session")
    }

    // MARK: - Foregrounding out of a terminal error re-drives playback

    @Test("Foregrounding while stranded in a terminal error re-drives playback")
    func foregroundWhileErroredRestarts() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Start playing, then the player settles into a terminal error with no
        // reconnect armed (e.g. backoff exhausted). Playback is still intended.
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        harness.mockPlayer.simulateStateChange(to: .error(.maxReconnectAttemptsExceeded))
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        let playsBefore = harness.playCallCount

        // Returning to the foreground should re-drive playback rather than leave
        // it dead in the errored state (no reconnect is in flight to recover it).
        harness.controller.handleAppDidEnterBackground()
        harness.controller.handleAppWillEnterForeground()
        await harness.waitForAsync()

        #expect(harness.playCallCount > playsBefore,
               "Foregrounding while stranded in a terminal error should re-drive playback")
    }
}

#endif
