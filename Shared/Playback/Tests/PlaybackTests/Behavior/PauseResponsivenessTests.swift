//
//  PauseResponsivenessTests.swift
//  Playback
//
//  Guards the contract that pausing publishes the paused state without first
//  blocking on the audio-session teardown, that deferring the teardown can't
//  undo a subsequent activation, that the audible stop stays synchronous, and
//  that the deferred teardown survives the app being backgrounded on top of it.
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
///
/// `.serialized` is load-bearing, not tidiness. Nine tests here arm
/// `MockAudioSession.holdDeactivations()`, whose hold blocks the controller's
/// *detached* handback task — a Swift cooperative-pool thread — for up to
/// `deactivationHoldCap`. The pool does not spawn replacements for blocked
/// threads, so several tests holding concurrently on a 2-4 core runner could
/// drain it and wedge the step instead of producing clean per-test failures
/// (#807 review). Running one at a time bounds the blocked pool threads to
/// one.
@Suite("Pause responsiveness", .serialized)
@MainActor
struct PauseResponsivenessTests {

    /// Upper bound on how long a synchronous, non-blocking call may take
    /// before the suite treats it as wedged rather than merely slow.
    ///
    /// Deliberately far above any latency worth asserting on: it sits above
    /// the 30s `stallTolerantTimeout` wait budget (so a legitimately slow
    /// wait can't trip it) and below `MockAudioSession.deactivationHoldCap`
    /// (so a caller that blocked on the hold trips it before the hold
    /// self-releases). At 45s this cannot fire on the ~10.5s stall measured
    /// in CI run 31205214380, or on any multiple of it the run recorded.
    ///
    /// This is a liveness backstop, not a latency assertion — see its use
    /// sites, and the note there on why the two are not the same thing.
    private static let livenessBackstop: Duration = .seconds(45)

    @Test("stop() publishes the paused state without waiting out the deactivation")
    func stopPublishesPausedStateBeforeDeactivating() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        // Hold the deactivation open on a gate the test controls, so a `stop()`
        // that routes through it is unmistakable rather than merely slow.
        harness.mockSession.holdDeactivations()
        harness.controller.play()
        #expect(harness.sessionActivated)

        // Named for what it holds — the mock counts activations and
        // deactivations in one counter, so this is 1 here (the `play()`
        // above), not 0. Calling it `deactivateCallsBeforeStop` invited a
        // future reader to assert `== 0` or to read a delta as "deactivations
        // added", neither of which the value supports.
        let setActiveCallsBeforeStop = harness.mockSession.setActiveCallCount
        let elapsed = ContinuousClock().measure { harness.controller.stop() }

        // Everything a view binds to must already read as paused at the moment
        // control returns — SwiftUI cannot render until it does.
        #expect(harness.controller.isPlaying == false)
        #expect(harness.controller.isPlaybackRequested == false)
        // The primary check is an ordering one, not an elapsed-time bound. A
        // ~10.5s process stall (CI run 31205214380, #807) can inflate any
        // wall-clock measurement taken around `stop()`, so no *tight*
        // threshold could separate a healthy `stop()` from a regressed one
        // under load. ("One second sits far from both, so scheduler
        // preemption can't fail a healthy run spuriously" was that run's own
        // counterexample: it took this test's `stop()` — never blocking on
        // anything — to a measured 1.2s.)
        //
        // The ordering check is immune to the stall rather than merely
        // tolerant of a wider one: `stop()` is a plain, non-`async` function,
        // and spawning a `Task` from synchronous, non-suspending code is
        // never itself a suspension point, so the deferred deactivation's
        // `Task` cannot have run by the time `stop()` returns control to a
        // synchronous caller — regardless of how slowly or quickly the
        // scheduler gets around to it afterward. A regressed `stop()` that
        // called `setActive(false, …)` inline instead of deferring it can
        // only return *after* that call resolves — including however long
        // the mock's hold keeps it open — so the call count having already
        // advanced is the tell, not how long it took to get here.
        #expect(
            harness.mockSession.setActiveCallCount == setActiveCallsBeforeStop,
            "stop() already called setActive(false, …) by the time it returned, so no view can render the paused state until the handback finishes"
        )
        // The backstop below is a different instrument, and the distinction
        // matters enough to state: the ordering check only detects a caller
        // that blocked *by calling `setActive`*. A `stop()` that wedged the
        // main actor some other way — a synchronous disk write, a
        // `beginHandbackAssertion()` round-trip, a lock acquired on a path
        // that returns `.stale` without ever touching the session — leaves
        // the count unchanged and passes. `livenessBackstop` is what notices
        // that, and it can do so without measuring the scheduler because it
        // is nowhere near any real latency: 45s is 4x the observed stall and
        // is not a claim that a healthy `stop()` takes under 45s in any
        // meaningful sense. Do not tighten it toward a "real" latency number
        // — that is the bound #807 removed, and it fails for the reasons
        // above.
        #expect(
            elapsed < Self.livenessBackstop,
            "stop() blocked the main actor for \(elapsed) — it is wedged on something, whether or not it called setActive"
        )

        // It still has to happen — just not on the caller's turn.
        harness.mockSession.releaseDeactivations()
        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: stallTolerantTimeout)
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
        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: stallTolerantTimeout)
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
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")

        let playsBefore = harness.playCallCount
        // Total `setActive` calls, both directions — 2 by this point (the
        // activation from the first `play()` and the deactivation now being
        // held). Not an activation-only counter; the mock has none.
        let setActiveCallsBeforePlay = harness.mockSession.setActiveCallCount
        let elapsed = ContinuousClock().measure { harness.controller.play() }

        // An ordering check, not an elapsed-time bound — see #807 and the
        // matching restructure on `stopPublishesPausedStateBeforeDeactivating`
        // above for why a ~10.5s process stall makes any tight wall-clock
        // measurement here unreliable in both directions. `activate(_:)`
        // takes `sessionLock` only via `lockIfAvailable()` — a non-blocking
        // try-lock — so a healthy activation that finds it held declines with
        // `AudioSessionBusy()` immediately, without ever calling
        // `setActive(true, …)`. A regression that blocked on the lock
        // instead could only return *after* acquiring it, by which point it
        // would already have called `setActive(true, …)` — so the call
        // count having advanced already is the tell.
        #expect(
            harness.mockSession.setActiveCallCount == setActiveCallsBeforePlay,
            "play() already called setActive(true, …) by the time it returned — the freeze moved from the pause tap to the play tap"
        )
        // Catches a `play()` wedged on something that never calls
        // `setActive` — see the note at the matching backstop above for why
        // this is a liveness check rather than a latency one.
        #expect(
            elapsed < Self.livenessBackstop,
            "play() blocked the main actor for \(elapsed) — it is wedged on something, whether or not it called setActive"
        )
        // The gate is still shut, so the only correct move was to defer: a
        // play() that started the player here either blocked (caught above) or
        // activated a session the handback still holds.
        #expect(harness.playCallCount == playsBefore, "play() started the player without the session — the deferral never engaged")

        // Deferring is only acceptable because the handback's own completion
        // finishes the job.
        harness.mockSession.releaseDeactivations()
        await harness.waitUntil({ harness.sessionActivated }, timeout: stallTolerantTimeout)
        #expect(harness.sessionActivated, "the deferred activation never completed")
        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: stallTolerantTimeout)
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
        }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivationSettled, "precondition: the failed handback never settled")

        // No intervening play(): the session is still active as far as the OS is
        // concerned, so the next stop() has to attempt the handback again rather
        // than early-out on a session it wrongly believes is already inactive.
        // Asserted on the call count, not `lastActiveState` — the mock records
        // the attempted state before it throws, so that flag can't distinguish a
        // failed deactivation from a successful one.
        harness.mockSession.shouldThrowOnDeactivate = false
        let callsBeforeRetry = harness.mockSession.setActiveCallCount
        // The retrying stop arrives with no standing intent and an idle player,
        // which is exactly what #933's idempotency guard short-circuits. That
        // is why `scheduleAudioSessionDeactivation()` sits outside the guard —
        // and this test is the reason it has to. Recorded here rather than in a
        // second copy of this setup over in `RedundantStopIdempotencyTests`.
        let teardownsBeforeRetry = harness.mockPlayer.stopCallCount

        harness.controller.stop()

        await harness.waitUntil({ harness.mockSession.setActiveCallCount > callsBeforeRetry }, timeout: stallTolerantTimeout)
        #expect(
            harness.mockSession.setActiveCallCount > callsBeforeRetry,
            "a failed deactivation abandoned the session — it is never handed back and other apps can't resume"
        )
        #expect(
            harness.mockPlayer.stopCallCount == teardownsBeforeRetry,
            "retrying the handback dragged a whole teardown along with it — a fresh MP3StreamDecoder for a player that is already stopped (#933)"
        )
    }

    @Test("A stop() that lands while a handback is in flight is still honoured")
    func stopDuringInFlightDeactivationStillHandsBack() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // All of these land in one main-actor turn, so the handback the first
        // stop() scheduled has not begun when the second one arrives: the task
        // that runs it cannot start until this turn ends. That makes the
        // interleaving deterministic rather than a race — but it is the same one
        // a real pause/play/pause hits whenever the second pause falls inside
        // the hundreds of milliseconds the handback takes on a device.
        harness.controller.play()
        harness.controller.stop()
        harness.controller.play()
        harness.controller.stop()
        // #933: echoes of that second stop must neither replace the handback
        // nor undo it. Recorded here rather than in a second copy of this
        // setup over in `RedundantStopIdempotencyTests` — the interleaving
        // above is delicate, and two copies of it drift.
        harness.controller.stop()
        harness.controller.stop()
        harness.controller.stop()

        // The first handback correctly declines as stale — the middle play()
        // re-activated the session out from under it. Something still has to
        // hand the session back for the *second* stop(), or the app keeps the
        // session for a pause the user can see took effect, and every other
        // audio app stays suppressed until the next play/stop cycle.
        await harness.waitUntil(
            { harness.sessionDeactivated && harness.sessionDeactivationSettled },
            timeout: stallTolerantTimeout
        )
        #expect(
            harness.sessionDeactivated,
            "the second stop() was swallowed by the in-flight guard and the session was never handed back"
        )
        #expect(
            harness.stopCallCount == 2,
            "only the two genuine stops should have torn down; got \(harness.stopCallCount)"
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
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: stallTolerantTimeout)
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
        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: stallTolerantTimeout)
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

    @Test("A hard activation failure after the handback escalates instead of spinning out the retries")
    func hardActivationFailureAfterHandbackEscalates() async {
        // A short bounded-retry cadence so a wrongly-scheduled budget runs out
        // well inside the await below rather than masking the missing signal.
        let harness = PlayerControllerTestHarness.make(
            for: .audioPlayerController,
            sessionActivationRetryDelay: .milliseconds(10)
        )
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")

        let playsBefore = harness.playCallCount
        harness.controller.play()
        #expect(harness.playCallCount == playsBefore, "precondition: the play was not deferred")

        // The session comes back broken: every later activation fails with a
        // generic (non-'!int') error. Reached directly through play() this
        // class of failure escalates recovery immediately (#518, design 6-A);
        // reached through the handback's re-drive it must do the same, not
        // burn a doomed bounded budget and then give up in silence for the
        // rest of the watchdog deadline.
        harness.mockSession.shouldThrowOnSetActive = true
        harness.mockSession.releaseDeactivations()

        await harness.waitUntil({
            harness.streamErrorEvents.contains(where: { $0.errorType == .silentStartup })
        }, timeout: stallTolerantTimeout)
        #expect(
            harness.streamErrorEvents.contains(where: { $0.errorType == .silentStartup }),
            "the hard failure was fed to the bounded retry, whose exhaustion gives up without escalating"
        )
    }

    #if os(iOS)
    @Test("An interruption ending mid-handback leaves the deferred play parked on the handback")
    func interruptionEndedDuringHandbackKeepsDeferredPlayParked() async {
        // A short bounded-retry cadence (4 × 10ms) so the adversarial wait
        // below can outlast the whole budget in a fraction of a second.
        let harness = PlayerControllerTestHarness.make(
            for: .audioPlayerController,
            sessionActivationRetryDelay: .milliseconds(10)
        )
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")

        let playsBefore = harness.playCallCount
        harness.controller.play()
        #expect(harness.playCallCount == playsBefore, "precondition: the play was not deferred")

        // A Siri query / alarm / declined call ends while the handback still
        // holds the session. `wasPlayingBeforeInterruption` is false (the play
        // is still deferred), so this routes through
        // `reactivateAfterInterruptionIfPending()` — which must notice the
        // blocker is our own handback and stay parked on its completion, not
        // demote the wait onto the bounded budget.
        harness.postInterruptionEnded(shouldResume: false)

        // Keep the gate shut past the entire bounded budget: a demoted wait
        // exhausts here, clears pendingPlaybackReason, and can never resume
        // once the gate opens.
        try? await Task.sleep(for: .milliseconds(200))
        harness.mockSession.releaseDeactivations()

        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: stallTolerantTimeout)
        #expect(
            harness.playCallCount > playsBefore,
            "the deferred play was abandoned when the demoted retry budget ran out"
        )
        #expect(harness.sessionActivated, "the session was never re-activated")
        #expect(
            harness.streamErrorEvents.filter({ $0.errorType == .silentStartup }).isEmpty,
            "waiting out our own handback was reported as a silent startup"
        )
    }

    @Test("A backgrounded resume colliding with the handback defers instead of escalating")
    func backgroundedPlayDuringHandbackDefersRatherThanEscalating() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: stallTolerantTimeout)
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
        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: stallTolerantTimeout)
        #expect(harness.playCallCount > playsBefore, "the backgrounded resume never started the player")
        #expect(harness.sessionActivated, "the backgrounded resume never re-activated the session")
        #expect(
            harness.streamErrorEvents.filter({ $0.errorType == .silentStartup }).isEmpty,
            "waiting out our own handback was reported as a silent startup"
        )
    }

    @Test("Backgrounding mid-handback keeps the deferred play alive")
    func backgroundingDuringHandbackPreservesDeferredPlay() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")

        // The play lands while the handback holds the session — it defers —
        // and THEN the user locks the phone. The inverse ordering (background,
        // then play) is covered above; this is the pause → play → pocket
        // sequence. The deferral's driver is the handback continuation, which
        // deliberately runs regardless of foreground state, so backgrounding
        // must not wipe the deferral bookkeeping out from under it.
        let playsBefore = harness.playCallCount
        harness.controller.play()
        #expect(harness.playCallCount == playsBefore, "precondition: the play was not deferred")
        harness.controller.handleAppDidEnterBackground()

        harness.mockSession.releaseDeactivations()
        await harness.waitUntil({ harness.playCallCount > playsBefore }, timeout: stallTolerantTimeout)
        #expect(
            harness.playCallCount > playsBefore,
            "backgrounding wiped the deferred play — the lock-screen play is lost until the next foreground"
        )
        #expect(harness.sessionActivated, "the deferred play never re-activated the session")
        #expect(
            harness.streamErrorEvents.filter({ $0.errorType == .silentStartup }).isEmpty,
            "a deferral we imposed on ourselves was reported as a silent startup"
        )
    }

    @Test("A pause the user backgrounds out of still hands the session back")
    func handbackSurvivesBackgroundingRightAfterAPause() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        // Hold the handback open across the background transition, which is the
        // whole scenario: swiping up or locking the screen takes far less time
        // than the XPC round-trip the pause tap just started.
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        // Asserted, not assumed, and waited for rather than inferred from the
        // synchronous flag: the gate records the call before it blocks, so this
        // proves the handback is *inside* `setActive(false, …)` right now. Had
        // it already finished, the background transition would take the
        // synchronous path and everything below would pass without ever
        // exercising the race this test is about.
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")
        #expect(
            harness.sessionDeactivationSettled == false,
            "precondition: the handback had already finished, so nothing was in flight to lose"
        )

        let eventsBeforeBackgrounding = harness.mockBackgroundTasks.events
        // Total `setActive` calls, both directions — see the note on the same
        // pattern in `stopPublishesPausedStateBeforeDeactivating`.
        let setActiveCallsBeforeBackgrounding = harness.mockSession.setActiveCallCount
        let elapsed = ContinuousClock().measure { harness.controller.handleAppDidEnterBackground() }

        // An ordering check, not an elapsed-time bound — see #807. Waiting out the in-flight
        // handback here would be worse than the freeze #774 removed: a
        // blocked main actor during a scenePhase transition is a watchdog
        // kill, not a stutter — but a ~10.5s process stall makes any
        // wall-clock measurement of that unreliable in both directions, the
        // same as the two restructured checks above. `deactivateAudioSessionOnCallersTurn()`
        // checks the plain `sessionDeactivationInFlight` flag before ever
        // touching `sessionLock`, and defers (`sessionDeactivationRequested
        // = true`) without calling `setActive(false, …)` again when it finds
        // a handback already running. A regression that skipped the flag
        // check and re-entered the (blocking) lock directly could only
        // return *after* acquiring it and calling `setActive(false, …)`
        // again — so the call count having advanced a second time is the
        // tell.
        #expect(
            harness.mockSession.setActiveCallCount == setActiveCallsBeforeBackgrounding,
            "the background transition already called setActive(false, …) again by the time it returned, instead of deferring to the handback already in flight"
        )
        // A wedged scenePhase transition is a watchdog kill in production, so
        // the backstop matters more here than anywhere else in the suite —
        // including for a block that never re-enters `setActive`. Liveness,
        // not latency; see the note at the first backstop above.
        #expect(
            elapsed < Self.livenessBackstop,
            "handleAppDidEnterBackground() blocked the main actor for \(elapsed) — a blocked scenePhase transition is a watchdog kill, not a stutter"
        )
        // Without an explicit request for background execution, whether the
        // handback's continuation runs at all is down to how fast the system
        // suspends us — and when it loses, `.notifyOthersOnDeactivation` never
        // fires and Spotify (or whatever WXYC interrupted) stays silent.
        #expect(
            harness.mockBackgroundTasks.activeCount >= 1,
            "nothing asked the system for the time to finish the handback, so it is racing suspension"
        )
        // Read *before* the transition, because reading it after can't tell the
        // two designs apart: an assertion begun inside
        // `handleAppDidEnterBackground()` would also leave one live here, and it
        // would cover only the tail of a handback that is already in flight by
        // then. Beginning it where the handback is scheduled is the whole point.
        #expect(
            eventsBeforeBackgrounding.count == 1 && eventsBeforeBackgrounding[0].isBegin,
            "the assertion was taken at the background transition rather than when the handback was scheduled: \(eventsBeforeBackgrounding)"
        )

        harness.mockSession.releaseDeactivations()
        await harness.waitUntil({
            harness.sessionDeactivated && harness.sessionDeactivationSettled
        }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivated, "the session was never handed back")
        #expect(
            harness.mockSession.lastActiveOptions == .notifyOthersOnDeactivation,
            "the handback dropped the notification other apps resume on"
        )
        #expect(
            harness.mockBackgroundTasks.activeCount == 0,
            "the background-execution assertion outlived the work it was taken for — the OS kills apps for that"
        )
    }
    #endif

    @Test("A failed handback still releases its background-execution assertion")
    func failedHandbackReleasesItsAssertion() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.mockSession.shouldThrowOnDeactivate = true

        harness.controller.play()
        harness.controller.stop()

        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivationSettled, "precondition: the failed handback never settled")
        #expect(harness.mockBackgroundTasks.beginCount >= 1, "precondition: no assertion was ever taken")

        // An assertion the app never ends is a termination, and it lands on
        // whatever the user does next rather than on the pause that leaked it.
        #expect(
            harness.mockBackgroundTasks.activeCount == 0,
            "a handback that threw walked away holding a background-execution assertion"
        )
        #expect(
            harness.mockBackgroundTasks.strayEndCount == 0,
            "the same assertion was ended twice — UIApplication treats that as a programming error"
        )
    }

    @Test("A handback that declines as stale still releases its assertion")
    func staleHandbackReleasesItsAssertion() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.controller.stop()
        // Re-activates the session out from under the scheduled handback, which
        // then recognises itself as stale and never calls `setActive` at all.
        harness.controller.play()

        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivationSettled, "precondition: the stale handback never settled")
        #expect(harness.mockBackgroundTasks.beginCount >= 1, "precondition: no assertion was ever taken")

        #expect(
            harness.mockBackgroundTasks.activeCount == 0,
            "a handback that declined to run walked away holding a background-execution assertion"
        )
        #expect(
            harness.mockBackgroundTasks.strayEndCount == 0,
            "the same assertion was ended twice — UIApplication treats that as a programming error"
        )
    }

    @Test("An expiring assertion is released rather than truncating the handback")
    func expiringAssertionIsReleasedWithoutASecondSetActive() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.mockSession.holdDeactivations()

        harness.controller.play()
        harness.controller.stop()
        // Wait until the handback is genuinely inside `setActive(false, …)`, so
        // the expiry below lands on work that is still running — expiring an
        // assertion whose task already finished proves nothing. The gate records
        // the call before blocking, so this edge is the handback holding the
        // session rather than merely having been scheduled.
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivated, "precondition: the handback never started holding the session")
        #expect(harness.mockBackgroundTasks.activeCount == 1, "precondition: no assertion was taken for the handback")

        harness.mockBackgroundTasks.expireAll()

        // Not ending an expired assertion is the one failure mode the OS
        // punishes immediately: it kills the process outright.
        #expect(
            harness.mockBackgroundTasks.activeCount == 0,
            "the expiration handler left the assertion live, which is a termination rather than a warning"
        )

        harness.mockSession.releaseDeactivations()
        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivationSettled, "precondition: the handback never settled")
        // One activation plus one handback, and nothing else. Expiry deliberately
        // does *not* force the handback to completion: a `setActive(false, …)`
        // that has outlived the whole background grace period is wedged in
        // mediaserverd, and a second one can only stack behind the first — while
        // blocking to issue it is the main-actor freeze this all exists to avoid.
        // `audioSessionActivated` stays set on an unconfirmed handback, so the
        // next stop() retries it instead.
        #expect(
            harness.mockSession.setActiveCallCount == 2,
            "expiry issued a second setActive behind one that was already in flight"
        )
        #expect(
            harness.mockBackgroundTasks.strayEndCount == 0,
            "the same assertion was ended twice — UIApplication treats that as a programming error"
        )
    }

    @Test("A re-driven handback holds its assertion before the one that scheduled it lets go")
    func redrivenHandbackNeverLetsTheAssertionLapse() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Same one-turn interleaving as `stopDuringInFlightDeactivationStillHandsBack`:
        // the first handback declines as stale and the second stop()'s recorded
        // request is re-driven from its continuation.
        harness.controller.play()
        harness.controller.stop()
        harness.controller.play()
        harness.controller.stop()

        await harness.waitUntil({ harness.mockBackgroundTasks.events.count == 4 }, timeout: stallTolerantTimeout)
        #expect(harness.mockBackgroundTasks.beginCount == 2, "precondition: the recorded request was never re-driven")

        // If the first assertion ends before the re-drive takes its own, there is
        // a window in which the app holds none — and it is exactly the window the
        // re-driven handback runs in, which is the one that actually hands the
        // session back.
        #expect(
            harness.mockBackgroundTasks.events[1].isBegin,
            "the assertion lapsed between the stale handback and the re-drive it scheduled: \(harness.mockBackgroundTasks.events)"
        )
        #expect(harness.mockBackgroundTasks.activeCount == 0, "an assertion was left live")
        #expect(harness.sessionDeactivated, "the re-driven handback never handed the session back")
    }

    @Test("A re-drive after expiry does not arm a fresh assertion against a spent budget")
    func redriveAfterExpiryDoesNotRearmTheAssertion() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // The re-drive interleaving again, but with the system taking our
        // background time away mid-flight.
        harness.controller.play()
        harness.controller.stop()
        harness.controller.play()
        harness.controller.stop()
        #expect(harness.mockBackgroundTasks.beginCount == 1, "precondition: the handback took no assertion to expire")

        harness.mockBackgroundTasks.expireAll()
        #expect(harness.mockBackgroundTasks.activeCount == 0, "precondition: expiry left an assertion live")

        await harness.waitUntil({
            harness.sessionDeactivated && harness.sessionDeactivationSettled
        }, timeout: stallTolerantTimeout)

        // Expiry is app-wide and means `backgroundTimeRemaining` is spent. Arming
        // another assertion there is the churn the expiration handler already
        // refuses to do by the front door — and its handler may not be delivered
        // before the process is suspended, which leaves it live and unended, the
        // one failure the OS punishes with termination rather than a warning.
        #expect(
            harness.mockBackgroundTasks.beginCount == 1,
            "a re-drive armed a new assertion after the system said our background time was spent: \(harness.mockBackgroundTasks.events)"
        )
        // Suppressing the *assertion* must not suppress the handback: it is still
        // the only thing that lets the interrupted app resume, and it runs exactly
        // as it did before this seam existed — unprotected, but never blocked.
        #expect(harness.sessionDeactivated, "suppressing the post-expiry assertion also dropped the handback")
        #expect(harness.mockBackgroundTasks.activeCount == 0, "an assertion was left live")
        #expect(harness.mockBackgroundTasks.strayEndCount == 0, "an assertion was ended twice")
    }

    @Test("A declined assertion leaves the handback unprotected but still running")
    func declinedAssertionStillCompletesTheHandback() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        // Background execution can be refused outright — the system returns an
        // invalid identifier and there is nothing to end. The handback must still
        // happen; it simply races suspension exactly as it did before #776.
        harness.mockBackgroundTasks.shouldDeclineToBegin = true

        harness.controller.play()
        harness.controller.stop()

        await harness.waitUntil({
            harness.sessionDeactivated && harness.sessionDeactivationSettled
        }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivated, "a declined assertion stopped the handback from happening at all")
        #expect(
            harness.mockSession.lastActiveOptions == .notifyOthersOnDeactivation,
            "the handback dropped the notification other apps resume on"
        )
        #expect(harness.mockBackgroundTasks.beginCount == 0, "precondition: the system did not actually decline")
        #expect(
            harness.mockBackgroundTasks.strayEndCount == 0,
            "an identifier the system never issued was handed back to it"
        )
    }

    #if os(iOS)
    @Test("An expired assertion leaves the handback for the next background transition to finish")
    func expiredHandbackIsRetriedByTheNextBackgrounding() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        // The handback comes back unconfirmed, which is the state expiry leaves
        // behind: the assertion is gone and nothing proved the session was
        // released. Letting it lapse is only defensible if something later picks
        // it up, so this pins what that something is.
        harness.mockSession.shouldThrowOnDeactivate = true

        harness.controller.play()
        harness.controller.stop()
        #expect(harness.mockBackgroundTasks.activeCount == 1, "precondition: no assertion was taken for the handback")
        harness.mockBackgroundTasks.expireAll()

        await harness.waitUntil({ harness.sessionDeactivationSettled }, timeout: stallTolerantTimeout)
        #expect(harness.sessionDeactivationSettled, "precondition: the expired handback never settled")

        // Foregrounding is deliberately *not* tested as a retry driver:
        // `handleAppWillEnterForeground()` touches the session only when
        // playback is intended, and a pause is exactly the state where it isn't.
        // Backgrounding is, because it finds `audioSessionActivated` still set
        // and hands back on the caller's turn.
        harness.mockSession.shouldThrowOnDeactivate = false
        let callsBeforeRetry = harness.mockSession.setActiveCallCount
        let assertionsBeforeRetry = harness.mockBackgroundTasks.beginCount

        harness.controller.handleAppDidEnterBackground()

        #expect(
            harness.mockSession.setActiveCallCount == callsBeforeRetry + 1,
            "the unconfirmed handback was dropped rather than retried, so the session is still held"
        )
        #expect(
            harness.mockSession.lastActiveOptions == .notifyOthersOnDeactivation,
            "the retry dropped the notification other apps resume on"
        )
        // The synchronous branch runs entirely within the caller's turn, and the
        // system does not suspend an app inside its own scenePhase callback — so
        // it takes no assertion, and taking one here would be an assertion begun
        // and ended in the same turn for nothing.
        #expect(
            harness.mockBackgroundTasks.beginCount == assertionsBeforeRetry,
            "the synchronous handback took a background-execution assertion it does not need"
        )
        #expect(harness.mockBackgroundTasks.activeCount == 0, "an assertion was left live")
        #expect(harness.mockBackgroundTasks.strayEndCount == 0, "an assertion was ended twice")
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
