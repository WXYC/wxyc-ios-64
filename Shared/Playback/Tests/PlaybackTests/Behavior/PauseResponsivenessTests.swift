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
        // Hold the deactivation open for far longer than the XPC call really
        // takes, so a `stop()` that waits for it is unmistakable. Asserted on
        // elapsed time rather than on the mock's recorded state: reading that
        // from the main actor immediately after `stop()` races the detached
        // deactivation, which is the very non-determinism this suite exists to
        // keep out of the codebase.
        harness.mockSession.deactivationDelay = 0.5
        harness.controller.play()
        #expect(harness.sessionActivated)

        let timer = ContinuousClock().now
        harness.controller.stop()
        let elapsed = ContinuousClock().now - timer

        // Everything a view binds to must already read as paused at the moment
        // control returns — SwiftUI cannot render until it does.
        #expect(harness.controller.isPlaying == false)
        #expect(harness.controller.isLoading == false)
        #expect(
            elapsed < .milliseconds(250),
            "stop() blocked for \(elapsed) on the deactivation, so no view can render the paused state until it finishes"
        )

        // It still has to happen — just not on the caller's turn.
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: .seconds(5))
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

        // Settle: play() either activated outright or deferred behind the
        // in-flight deactivation and re-activated on the bounded retry.
        await harness.waitUntil({ harness.sessionActivated }, timeout: .seconds(5))
        // Then give any straggling deactivation a chance to land late.
        await harness.waitUntil({ false }, timeout: .milliseconds(200))

        #expect(
            harness.sessionActivated,
            "the deferred deactivation tore down a session that play() had already re-activated"
        )
    }

    @Test("play() defers rather than blocking behind an in-flight deactivation")
    func playDoesNotBlockBehindDeactivation() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        // Hold the deactivation open for far longer than the XPC call really
        // takes, so a main actor that waits on it is unmistakable.
        harness.mockSession.deactivationDelay = 0.5

        harness.controller.play()
        harness.controller.stop()
        // Let the detached deactivation reach `setActive(false, …)` and start
        // holding the session.
        await harness.waitUntil({ harness.sessionDeactivated }, timeout: .seconds(5))

        let timer = ContinuousClock().now
        harness.controller.play()
        let elapsed = ContinuousClock().now - timer

        #expect(
            elapsed < .milliseconds(250),
            "play() blocked for \(elapsed) waiting out the deactivation — the freeze moved from the pause tap to the play tap"
        )

        // Deferring is only acceptable because the bounded retry finishes the job.
        await harness.waitUntil({ harness.sessionActivated }, timeout: .seconds(5))
        #expect(harness.sessionActivated, "the deferred activation never completed")
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
            harness.mockSession.setActiveCallCount >= 2
                && harness.audioController?.debugStateSnapshot
                    .contains("sessionDeactivationInFlight=false") == true
        }, timeout: .seconds(5))

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
}

#endif
