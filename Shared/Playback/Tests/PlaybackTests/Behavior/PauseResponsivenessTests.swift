//
//  PauseResponsivenessTests.swift
//  Playback
//
//  Guards the contract that pausing publishes the paused state without first
//  blocking on the audio-session teardown, that deferring the teardown can't
//  undo a subsequent activation, and that the audible stop stays synchronous.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import AVFoundation
import PlaybackTestUtilities
import Analytics
import AnalyticsTesting
@testable import Playback
@testable import PlaybackCore

#if os(iOS) || os(tvOS)

/// `AVAudioSession.setActive(false, options: .notifyOthersOnDeactivation)` is a
/// synchronous XPC round-trip to `mediaserverd` that also fans resume
/// notifications out to every other audio app on the device. Running it inline
/// in `stop()` put that latency between the user's tap and SwiftUI's next
/// render — the caller's turn has to return before any view can update — which
/// left the pause button and the LCD visualizer visibly frozen. These tests pin
/// the deferral, the interlock that keeps it safe, and its limit.
@Suite("Pause responsiveness")
@MainActor
struct PauseResponsivenessTests {

    @Test("stop() publishes the paused state without waiting out the deactivation")
    func stopPublishesPausedStateBeforeDeactivating() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        // Hold the deactivation open on a gate the test controls, so a `stop()`
        // that waits for it is unmistakable: a healthy stop() returns while the
        // gate is still shut, and a regressed one blocks into the gate's safety
        // cap and fails the elapsed bound below. Asserted on elapsed time
        // rather than on the mock's recorded state: reading that from the main
        // actor immediately after `stop()` races the detached deactivation,
        // which is the very non-determinism this suite exists to keep out of
        // the codebase.
        harness.mockSession.holdDeactivations()
        harness.controller.play()
        #expect(harness.sessionActivated)

        let timer = ContinuousClock().now
        harness.controller.stop()
        let elapsed = ContinuousClock().now - timer

        // Everything a view binds to must already read as paused at the moment
        // control returns — SwiftUI cannot render until it does.
        #expect(harness.controller.isPlaying == false)
        #expect(harness.controller.isLoading == false)
        // A healthy stop() measures ~0ms; a regressed one blocks into the 5s
        // safety cap. One second sits far from both, so scheduler preemption
        // can't fail a healthy run spuriously.
        #expect(
            elapsed < .seconds(1),
            "stop() blocked for \(elapsed) on the deactivation, so no view can render the paused state until it finishes"
        )

        // It still has to happen — just not on the caller's turn.
        harness.mockSession.releaseDeactivations()
        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: .seconds(5))
        #expect(harness.sessionDeactivated)
    }

    @Test("Deferring the teardown does not defer the audible stop")
    func audibleStopStaysSynchronous() {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.controller.play()
        let stopsBefore = harness.stopCallCount

        harness.controller.toggle()

        #expect(
            harness.stopCallCount == stopsBefore + 1,
            "the player itself must stop on the caller's turn; only the session teardown is deferred"
        )
        #expect(
            harness.analyticsStopCallCount == 1,
            "the pause event must be captured on the caller's turn too"
        )
    }

    @Test("A deferred deactivation never lands on a session play() re-activated")
    func deferredDeactivationYieldsToReactivation() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.controller.play()

        // Pause and immediately resume, before the deferred teardown can run.
        harness.controller.stop()
        harness.controller.play()

        // Wait on the deactivation actually having run and decided, rather than
        // on a fixed delay: `sessionDeactivationInFlight` is set synchronously by
        // stop() and cleared only in the continuation, so it is an edge the test
        // can observe instead of a duration it has to guess.
        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: .seconds(5))
        #expect(harness.sessionDeactivationSettled, "the deferred deactivation never ran")

        #expect(
            harness.sessionActivated,
            "the deferred deactivation tore down a session that play() had already re-activated"
        )
        // Stronger than `lastActiveState`, which only records the most recent
        // call: two activations and no deactivation is the only history in which
        // the stale check actually declined.
        #expect(
            harness.mockSession.setActiveCallCount == 2,
            "the stale deactivation called setActive anyway"
        )
    }

    @Test("play() defers rather than blocking behind an in-flight deactivation")
    func playDoesNotBlockBehindDeactivation() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        // Hold the deactivation open on the test's gate, so the session lock is
        // provably still held when the play() below arrives — a wall-clock hold
        // could lapse on a stalled scheduler and turn the rest of the test into
        // a vacuous pass that never exercises the deferral.
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        // Let the detached deactivation reach `setActive(false, …)` and start
        // holding the session. Asserted, not assumed: `waitUntil` returns
        // silently on timeout.
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: .seconds(5))
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")

        let playsBefore = harness.playCallCount
        let timer = ContinuousClock().now
        harness.controller.play()
        let elapsed = ContinuousClock().now - timer

        // A healthy play() measures ~0ms; a regressed one blocks into the 5s
        // safety cap. One second sits far from both.
        #expect(
            elapsed < .seconds(1),
            "play() blocked for \(elapsed) waiting out the deactivation — the freeze moved from the pause tap to the play tap"
        )
        // The gate is still shut, so the only correct move was to defer: a
        // play() that started the player here either blocked (caught above) or
        // activated a session the handback still holds.
        #expect(harness.playCallCount == playsBefore, "play() started the player without the session — the deferral never engaged")

        // Deferring is only acceptable because the handback's own completion
        // finishes the job.
        harness.mockSession.releaseDeactivations()
        await harness.waitUntil({ harness.sessionActivated }, timeout: .seconds(5))
        #expect(harness.sessionActivated, "the deferred activation never completed")
        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: .seconds(5))
        #expect(harness.playCallCount > playsBefore, "the deferred play never started the player")
    }

    @Test("A failed deactivation leaves the session retryable")
    func failedDeactivationStaysRetryable() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.mockSession.shouldThrowOnDeactivate = true

        harness.controller.play()
        harness.controller.stop()
        // Wait for the failure to have been fully processed, not merely
        // attempted: the retry is gated on the in-flight guard clearing, which
        // happens a continuation later than the mock records the call.
        await harness.waitUntil({
            harness.mockSession.setActiveCallCount >= 2 && harness.sessionDeactivationSettled
        }, timeout: .seconds(5))
        #expect(harness.sessionDeactivationSettled, "precondition: the failed handback never settled")

        // No intervening play(): the session is still active as far as the OS is
        // concerned, so the next stop() has to attempt the handback again rather
        // than early-out on a session it wrongly believes is already inactive.
        // Asserted on the call count, not `lastActiveState` — the mock records
        // the attempted state before it throws, so that flag can't distinguish a
        // failed deactivation from a successful one.
        harness.mockSession.shouldThrowOnDeactivate = false
        let callsBeforeRetry = harness.mockSession.setActiveCallCount

        harness.controller.stop()

        await harness.waitUntil({ harness.mockSession.setActiveCallCount > callsBeforeRetry }, timeout: .seconds(5))
        #expect(
            harness.mockSession.setActiveCallCount > callsBeforeRetry,
            "a failed deactivation abandoned the session — it is never handed back and other apps can't resume"
        )
    }

    @Test("A stop() that lands while a handback is in flight is still honoured")
    func stopDuringInFlightDeactivationStillHandsBack() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // All four calls land in one main-actor turn, so the handback the first
        // stop() scheduled has not begun when the second one arrives: the task
        // that runs it cannot start until this turn ends. That makes the
        // interleaving deterministic rather than a race — but it is the same one
        // a real pause/play/pause hits whenever the second pause falls inside
        // the hundreds of milliseconds the handback takes on a device.
        harness.controller.play()
        harness.controller.stop()
        harness.controller.play()
        harness.controller.stop()

        // The first handback correctly declines as stale — the middle play()
        // re-activated the session out from under it. Something still has to
        // hand the session back for the *second* stop(), or the app keeps the
        // session for a pause the user can see took effect, and every other
        // audio app stays suppressed until the next play/stop cycle.
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: .seconds(5))
        #expect(
            harness.sessionDeactivated,
            "the second stop() was swallowed by the in-flight guard and the session was never handed back"
        )
    }

    @Test("A handback slower than the retry budget still resumes playback promptly")
    func playResumesAfterHandbackOutlastsRetryBudget() async {
        // A short bounded-retry cadence (4 × 10ms) so the hold below can
        // outlast the entire budget in a fraction of a second. With the
        // production 250ms spacing the same hold would need to stay shut for
        // over a second of wall-clock — the budget-vs-handback race is about
        // ordering, not real time.
        let harness = PlayerControllerTestHarness.make(
            for: .audioPlayerController,
            sessionActivationRetryDelay: .milliseconds(10)
        )
        // Held on the test's gate: however long the handback takes, polling
        // alone would exhaust its bounded budget first and abandon the play —
        // the deferral must instead ride the handback's own completion.
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: .seconds(5))
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")

        let stopsBefore = harness.stopCallCount
        let playsBefore = harness.playCallCount
        harness.controller.play()
        #expect(harness.playCallCount == playsBefore, "precondition: the play was not deferred")

        // Keep the gate shut past the whole bounded budget: a deferral that was
        // (wrongly) demoted onto that budget exhausts here, clears its
        // bookkeeping, and can never resume once the gate opens.
        try? await Task.sleep(for: .milliseconds(200))
        harness.mockSession.releaseDeactivations()

        // The handback's own completion re-drives the deferred activation, so the
        // wait is proportional to the handback rather than to a fixed budget.
        // Asserted on the player actually being started, not on `isPlaying`: the
        // mock republishes state through `stateStream`, so a poll can catch a
        // stale `.playing` replayed from before the stop() and pass vacuously.
        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: .seconds(10))
        #expect(
            harness.playCallCount > playsBefore,
            "the play was abandoned when the retry budget ran out — the user is left on a spinner until the startup watchdog fires"
        )
        #expect(harness.sessionActivated, "the session was never re-activated")
        #expect(
            harness.streamErrorEvents.filter({ $0.errorType == .silentStartup }).isEmpty,
            "a deferral we imposed on ourselves was reported as a silent startup"
        )
        #expect(harness.stopCallCount == stopsBefore, "the player was torn down again while resuming")
    }

    #if os(iOS)
    @Test("A backgrounded resume colliding with the handback defers instead of escalating")
    func backgroundedPlayDuringHandbackDefersRatherThanEscalating() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: .seconds(5))
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")

        // Backgrounded is the *normal* state for the resumes that collide with a
        // handback — an interruption ending, a lock-screen or CarPlay play, a
        // route flap. The deferral is ours, so it must not be reported as the
        // app failing to make sound: `silent_startup` is the #518 fleet metric
        // for genuinely-silent startups, and a self-inflicted wait that lands in
        // it sends reliability triage after a signal we manufactured.
        harness.controller.handleAppDidEnterBackground()
        let playsBefore = harness.playCallCount
        harness.controller.play()
        #expect(harness.playCallCount == playsBefore, "precondition: the play was not deferred")

        harness.mockSession.releaseDeactivations()
        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: .seconds(10))
        #expect(harness.playCallCount > playsBefore, "the backgrounded resume never started the player")
        #expect(harness.sessionActivated, "the backgrounded resume never re-activated the session")
        #expect(
            harness.streamErrorEvents.filter({ $0.errorType == .silentStartup }).isEmpty,
            "waiting out our own handback was reported as a silent startup"
        )
    }

    @Test("Backgrounding hands the session back on the caller's turn")
    func backgroundingHandsBackWithoutDeferring() {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        // A widget or Siri tap warms the session without setting playback intent.
        harness.audioController?.prepareForPlayback()
        #expect(harness.sessionActivated, "precondition: the session was never activated")

        harness.controller.handleAppDidEnterBackground()

        // Asserted with no await, deliberately. Deferring buys nothing here —
        // nothing is rendering during a background transition — and costs the
        // one guarantee that mattered: a deferred handback races suspension, and
        // if it loses, `.notifyOthersOnDeactivation` never fires and the app
        // whose audio we interrupted stays silent until WXYC is next resumed.
        #expect(
            harness.sessionDeactivated,
            "the handback was deferred into a suspension it may not survive"
        )
    }
    #endif
}

#endif
