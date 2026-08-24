//
//  RedundantStopIdempotencyTests.swift
//  Playback
//
//  Idempotency of `AudioPlayerController.tearDown(reason:)` (#933). A stop against
//  a player with no standing intent and an idle mirror must tear nothing down
//  a second time — at most one `player.stop()` per stop request, no duplicate
//  `PlaybackStoppedEvent`, and no clobbering of the #665 sessionID /
//  `wasPlayingBeforeRouteDisconnect` state a pending auto-resume depends on.
//  The negative half matters just as much: a stop that arrives mid-connect,
//  mid-buffer, or against a still-active audio session must still do the whole
//  job.
//
//  The contract is stated against `AudioPlayerProtocol`, not against one
//  conformance: this controller also ships against `RadioPlayer` and
//  `HLSPlayer`. What a redundant `player.stop()` *costs* is the conformance's
//  business — today `MP3Streamer` allocates a decoder and spawns a consumer
//  task per call while its two siblings are free, which is #937.
//
//  Created by Jake Bromberg on 08/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import AVFoundation
import PlaybackTestUtilities
@testable import Playback
@testable import PlaybackCore

#if os(iOS) || os(tvOS)

/// Sentry IOS-5F recorded seven `stop()` calls in four seconds against a player
/// that had already gone idle, each one running the full teardown: a new
/// `MP3StreamDecoder`, a re-armed session deactivation, and another
/// `PlaybackStoppedEvent` on the #663 duration series.
///
/// Every assertion here is on a structural counter — `MockAudioPlayer`'s
/// `stopCallCount`, `MockAudioSession`'s `setActiveCallCount`, or a typed
/// analytics event — never on log text.
///
/// `stopCallCount` is the decoder-creation counter this layer can see:
/// `MP3Streamer.stop()` calls `resetStreamIO()` unconditionally, and
/// `resetStreamIO()` unconditionally does `mp3Decoder = MP3StreamDecoder()`.
/// One `player.stop()` is therefore exactly one decoder allocation, and the
/// decoder's own `instanceID` is private to `MP3StreamerModule`.
@Suite("Redundant Stop Idempotency Tests")
@MainActor
struct RedundantStopIdempotencyTests {

    // MARK: - The positive case: repeated stops must collapse to one

    @Test(
        "N consecutive stops against an idle controller tear down exactly once",
        arguments: [2, 3, 7]
    )
    func consecutiveStopsTearDownExactlyOnce(stopCount: Int) async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.stopCallCount == 0, "precondition: nothing has been torn down yet")

        for _ in 0..<stopCount {
            harness.controller.stop()
        }
        await harness.waitForAsync()

        #expect(
            harness.stopCallCount == 1,
            "\(stopCount) stops ran \(harness.stopCallCount) teardowns — each one allocates a fresh MP3StreamDecoder"
        )
    }

    @Test("Seven remote pause commands against an idle player emit one PlaybackStoppedEvent")
    func redundantRemotePauseCommandsEmitOneStoppedEvent() async throws {
        // The literal IOS-5F shape: `reason: remote pause command`, repeated,
        // with nothing playing. The command-center target is the one stop path
        // that captures its analytics event *before* delegating to `stop()`,
        // so it is where a guard placed only inside `stop()` still
        // double-counts. Driven through `handleRemotePauseCommand()` — the
        // whole body of that target — because `MPRemoteCommandEvent` raises
        // "MPRemoteCommandEvents cannot be initialized externally" on `init`,
        // so the closure itself cannot be called from a test.
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        for _ in 0..<7 {
            controller.handleRemotePauseCommand()
        }
        await harness.waitForAsync()

        let stoppedCount = harness.analyticsStopCallCount
        #expect(
            stoppedCount == 1,
            "seven pauses emitted \(stoppedCount) pause events — the stop count and the #663 duration series are inflated by every repeat"
        )
        #expect(
            harness.stopCallCount == 1,
            "seven pauses ran \(harness.stopCallCount) teardowns, allocating that many MP3StreamDecoders"
        )
    }

    // MARK: - The negative case: a stop with work to do must still do it

    @Test("A stop after a deferred session activation still tears down, with the mirror still idle")
    func stopAfterADeferredActivationStillTearsDown() async throws {
        // The production path that genuinely leaves a standing play request
        // over an idle mirror. `play()` sets the intent, then returns early at
        // `guard activateAudioSession() else` — `startPlayerAfterActivation`,
        // and with it `player.play()`, never runs — so the player has reported
        // nothing and `playerState` is still `.idle` while the listener is
        // looking at a pause button. Only the intent half of the predicate
        // catches a stop here.
        //
        // Modelled with the real `'!int'` CannotInterruptOthers failure (#514)
        // rather than a mute mock, and with a retry delay long enough that the
        // bounded retry cannot fire mid-test and start the player behind the
        // assertions. `stop()` cancels that retry via
        // `clearPendingSessionActivation()`.
        //
        // Note this is *not* "a stop mid-connect": MP3Streamer's `play()` sets
        // `streamingState = .connecting` synchronously and that surfaces as
        // `.loading`, so a real mid-connect stop is caught by the mirror half
        // and is covered by `stopWhileNonIdleStillTearsDown` below.
        let harness = PlayerControllerTestHarness.make(
            for: .audioPlayerController,
            sessionActivationRetryDelay: .seconds(60)
        )
        let controller = try #require(harness.audioController)
        harness.mockSession.shouldThrowOnSetActive = true
        harness.mockSession.setActiveError = MockAudioSession.cannotInterruptOthersError()

        harness.controller.play()

        #expect(harness.playCallCount == 0, "precondition: the deferral never started the player")
        #expect(controller.debugState.playerState == .idle, "precondition: the player has reported nothing")
        #expect(controller.debugState.playbackIntended, "precondition: the play intent is standing")

        harness.controller.stop()

        #expect(
            harness.stopCallCount == 1,
            "a stop over a deferred activation was swallowed — the listener's pause does nothing and the retry stays armed"
        )
        #expect(controller.debugState.playbackIntended == false, "the stop must clear the standing intent")
    }

    @Test("A stop mid-connect or mid-buffer still tears down", arguments: [PlayerState.loading, .stalled, .playing])
    func stopWhileNonIdleStillTearsDown(state: PlayerState) async throws {
        // MP3Streamer's `connecting`, `buffering`, and `reconnecting` all
        // surface at this layer as `.loading` (`play()` sets `.connecting`
        // synchronously, so the mirror is written before `play()` returns);
        // `.stalled` and `.playing` round out the non-idle set. All of them
        // arrive with intent standing too, so this pins the belt-and-braces
        // half of the predicate.
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)
        harness.mockPlayer.shouldAutoUpdateState = false

        harness.controller.play()
        harness.mockPlayer.simulateStateChange(to: state)
        await harness.waitUntil({ controller.debugState.playerState == state })
        #expect(controller.debugState.playerState == state, "precondition: the mirror never reached \(state)")

        harness.controller.stop()

        #expect(
            harness.stopCallCount == 1,
            "a stop during \(state) was swallowed"
        )
    }

    @Test("A non-idle state mirror alone is enough to tear down, with no standing intent")
    func stopTearsDownOnANonIdleMirrorWithoutIntent() async throws {
        // The state observer is fed by an async stream, so a `.loading` emitted
        // before a stop can be delivered after it. That leaves intent cleared
        // and the mirror non-idle — the one shape where the intent half of the
        // predicate says "nothing to do" and is wrong. A guard on intent alone
        // passes every other test in this file and fails this one.
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.controller.stop()
        await harness.waitForAsync()
        let teardownsAfterRealStop = harness.stopCallCount
        #expect(teardownsAfterRealStop == 1, "precondition: the real stop tore down once")

        harness.mockPlayer.simulateLateStateDelivery(.loading)
        await harness.waitUntil({ controller.debugState.playerState == .loading })
        #expect(controller.debugState.playerState == .loading, "precondition: the mirror never went stale")
        #expect(controller.debugState.playbackIntended == false, "precondition: no intent is standing")

        harness.controller.stop()

        #expect(
            harness.stopCallCount == teardownsAfterRealStop + 1,
            "the player was left running because the guard trusted the cleared intent over a non-idle mirror"
        )
    }

    // MARK: - #665: reasons that legitimately arrive while not playing

    // A route disconnect and an interruption both stop playback while leaving
    // auto-resume state standing (`wasPlayingBeforeRouteDisconnect`, the #665
    // session id), and both leave the controller in exactly the shape the
    // idempotency guard short-circuits: no intent, idle mirror. So the guard
    // decides whether that state can ever be retired again, and the answer has
    // to depend on the reason.
    //
    // The dividing line is `PlaybackStopTeardown`'s existing survival rule,
    // reused rather than re-derived. The duplicate-dispatch bug this all comes
    // from (#932) redelivers *the same command*, so a stray stop always carries
    // the same reason as the stop it duplicates — and the survival rule already
    // says "the reasons whose repeats must preserve are the reasons that set
    // the state." A stop arriving under any other reason is a new decision, not
    // an echo.

    #if os(iOS)
    @Test("A duplicate interruption-began stop preserves the session id (#665)")
    func duplicateInterruptionStopPreservesSessionID() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        let listenSessionID = try #require(controller.sessionID, "precondition: play() mints a session id")

        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()

        #expect(
            harness.stopCallCount == 1,
            "the interruption stop was swallowed — the stream keeps running under the interruption"
        )
        #expect(
            controller.sessionID == listenSessionID,
            "#665: an interruption is a prelude to auto-resume, so the session id has to survive it"
        )

        // The echo of that same stop — #932's shape. It must tear nothing down
        // and must not retire the id the pending resume is holding.
        harness.controller.tearDown(reason: .interruptionBegan)
        await harness.waitForAsync()

        #expect(harness.stopCallCount == 1, "the duplicate churned the decoder")
        #expect(
            controller.sessionID == listenSessionID,
            "a duplicate interruption stop retired the id the resume needs"
        )
    }

    @Test("A lock-screen pause after an interruption retires the session id")
    func lockScreenPauseAfterAnInterruptionRetiresTheSessionID() async throws {
        // The listener overrides the pending auto-resume by hand. The listen is
        // over: a play hours later must mint a fresh id rather than reopening
        // this one through `sessionID = sessionID ?? UUID()`, which would merge
        // two listens on the #663 duration series.
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        let listenSessionID = try #require(controller.sessionID)

        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()
        #expect(controller.sessionID == listenSessionID, "precondition: the id survived the interruption")

        controller.handleRemotePauseCommand()
        await harness.waitForAsync()

        #expect(
            controller.sessionID == nil,
            "a deliberate pause left the interruption's session id standing — the next listen merges into this one"
        )
        #expect(harness.stopCallCount == 1, "the pause churned the decoder")

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        #expect(
            controller.sessionID != listenSessionID,
            "the next listen reused the retired id"
        )
    }

    @Test("A duplicate route-disconnect stop preserves the auto-resume flag (#665)")
    func duplicateRouteDisconnectStopPreservesResumeFlag() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        let listenSessionID = try #require(controller.sessionID, "precondition: play() mints a session id")

        harness.postRouteChange(reason: .oldDeviceUnavailable)
        await harness.waitForAsync()

        #expect(
            harness.stopCallCount == 1,
            "the route-disconnect stop was swallowed — audio keeps playing out of the built-in speaker"
        )
        #expect(
            controller.wasPlayingBeforeRouteDisconnect,
            "the reconnect needs to know playback was active"
        )
        #expect(controller.sessionID == listenSessionID, "#665: the id survives a route disconnect")

        harness.controller.tearDown(reason: .routeDisconnected)
        await harness.waitForAsync()

        #expect(harness.stopCallCount == 1, "the duplicate churned the decoder")
        #expect(
            controller.wasPlayingBeforeRouteDisconnect,
            "a duplicate route-disconnect stop cleared the flag — reinserting the AirPod no longer resumes"
        )
        #expect(
            controller.sessionID == listenSessionID,
            "a duplicate route-disconnect stop retired the id the resume needs"
        )
    }

    @Test("A lock-screen pause after a route disconnect cancels the pending auto-resume")
    func lockScreenPauseAfterARouteDisconnectCancelsTheAutoResume() async throws {
        // The scenario the guard must not break: AirPods are yanked, audio
        // stops with `wasPlayingBeforeRouteDisconnect` standing, and the
        // listener — reacting to the silence — pauses from the Lock Screen.
        // That pause has to cancel the pending resume. If it doesn't,
        // reinserting the AirPods starts audio with no user action, which is
        // the same complaint class as the duplicate-stop bug this all fixes.
        //
        // Deliberately driven through `handleRemotePauseCommand()`: it is the
        // real lock-screen path, and it is the one stop site that reaches
        // `stop()` without an intent check ahead of it (`toggle(reason:)`
        // branches on `isPlaybackRequested`, so the in-app button cannot get
        // here).
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.postRouteChange(reason: .oldDeviceUnavailable)
        await harness.waitForAsync()
        #expect(controller.wasPlayingBeforeRouteDisconnect, "precondition: a resume is pending")
        let teardownsAfterDisconnect = harness.stopCallCount
        let stoppedEventsAfterDisconnect = harness.analyticsStopCallCount
        let playsAfterDisconnect = harness.playCallCount

        controller.handleRemotePauseCommand()
        await harness.waitForAsync()

        #expect(
            controller.wasPlayingBeforeRouteDisconnect == false,
            "the deliberate pause did not cancel the pending auto-resume"
        )
        #expect(controller.sessionID == nil, "the deliberate pause left the listen open")
        // Cancelling the resume is bookkeeping, not a second teardown: the
        // #933 wins have to survive it.
        #expect(
            harness.stopCallCount == teardownsAfterDisconnect,
            "cancelling the resume dragged a whole teardown along with it"
        )
        #expect(
            harness.analyticsStopCallCount == stoppedEventsAfterDisconnect,
            "the pause emitted a second PlaybackStoppedEvent for a listen the route disconnect already closed"
        )

        // The user-visible half: reinserting the AirPods must stay silent.
        harness.postRouteChange(reason: .newDeviceAvailable)
        await harness.waitForAsync()

        #expect(
            harness.playCallCount == playsAfterDisconnect,
            "reinserting the route resumed playback the listener had explicitly paused"
        )
    }

    @Test("A pause on top of an interruption cancels the interruption's auto-resume")
    func lockScreenPauseAfterAnInterruptionCancelsTheAutoResume() async throws {
        // The interruption analogue of the route-disconnect test above, and the
        // reason `retireAutoResumeState` cannot be the whole rule: it reaches
        // `wasPlayingBeforeRouteDisconnect` and the #665 session id, but
        // `wasPlayingBeforeInterruption` is private to
        // `PlaybackInterruptionRouteHandler` and is cleared only at the end of
        // `.ended`. Nothing on the stop path could reach it.
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // A phone call arrives: the handler stops playback and arms the resume.
        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()
        let playsAfterInterruption = harness.playCallCount

        // Mid-call, the listener pauses from the Lock Screen. That stop lands in
        // exactly the state #933's guard short-circuits — no standing intent,
        // idle mirror — so it is the *only* stop that will ever be delivered
        // here. If the armed resume outlives it, nothing else will retire it.
        harness.controller.tearDown(reason: .remotePauseCommand)
        await harness.waitForAsync()

        // The call ends and the system offers a resume.
        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()

        #expect(
            harness.playCallCount == playsAfterInterruption,
            "the interruption ending resumed audio the listener had explicitly paused"
        )
    }
    #endif

    // MARK: - A stop must not leave a reconnect armed behind it

    @Test("A stall delivered after a stop does not arm a reconnect")
    func staleStallAfterStopDoesNotArmAReconnect() async throws {
        // `player.eventStream` is an unbounded AsyncStream, so a `.stall`
        // yielded just before a stop is consumed just after it — the same
        // stale-delivery the state observer already defends against for
        // `.playing`. Reconnecting on it resurrects a stream the listener
        // stopped, and #933's guard means no later stop is guaranteed to cancel
        // the task: the mirror stays `.idle`, so every subsequent stop
        // short-circuits past the cancellation.
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop()
        await harness.waitForAsync()

        // Match `harness.simulateStall()`'s own discipline: without this the
        // mock auto-recovers and a reconnect would reset the counter it just
        // consumed, hiding the arming behind a zero.
        harness.mockPlayer.shouldAutoUpdateState = false
        harness.mockPlayer.simulateLateStall()

        // Wait the way the positive case below has to be waited for — the event
        // reaches `handleStall()` over an async stream, so a single
        // `waitForAsync()` returns before delivery and would pass vacuously.
        // Give the reconnect every chance to arm, then assert it didn't.
        await harness.waitUntil({ (harness.getBackoffAttempts() ?? 0) > 0 }, timeout: .seconds(1))

        #expect(
            harness.getBackoffAttempts() == 0,
            "a stall for playback nobody asked for started the reconnect ramp"
        )
    }

    @Test("A stall during playback still arms a reconnect")
    func liveStallStillArmsAReconnect() async throws {
        // The non-vacuity control for the test above: the staleness gate must
        // key on playback intent, not disable stall recovery outright. Without
        // this, dropping every `.stall` on the floor would pass.
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.simulateStall()
        await harness.waitUntil({ (harness.getBackoffAttempts() ?? 0) > 0 }, timeout: .seconds(2))

        #expect(
            (harness.getBackoffAttempts() ?? 0) > 0,
            "a genuine stall mid-listen did not start the reconnect ramp"
        )
    }

    // MARK: - The audio session must never be stranded

    // Both handback contracts are pinned in `PauseResponsivenessTests`, next to
    // the interleavings they depend on, rather than in a second copy here:
    // `failedDeactivationStaysRetryable` now also asserts that the retrying
    // stop tears nothing down, and `stopDuringInFlightDeactivationStillHandsBack`
    // now also pins that redundant stops piled on a cancelled handback neither
    // replace it nor undo it. Both setups are delicate and both would drift if
    // duplicated.
}

#endif
