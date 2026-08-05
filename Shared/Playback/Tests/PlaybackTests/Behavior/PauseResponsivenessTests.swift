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

    @Test("stop() publishes the paused state before deactivating the session")
    func stopPublishesPausedStateBeforeDeactivating() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        harness.controller.play()
        #expect(harness.sessionActivated)

        harness.controller.stop()

        // Everything a view binds to must already read as paused at the moment
        // control returns, with the blocking deactivation still outstanding.
        #expect(harness.controller.isPlaying == false)
        #expect(harness.controller.isLoading == false)
        #expect(
            harness.sessionDeactivated == false,
            "deactivation ran inline, so no view can render the paused state until it finishes"
        )

        // It still has to happen — just not on the caller's turn.
        await harness.waitUntil { harness.sessionDeactivated }
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

        // Give the deferred deactivation every chance to land late.
        await harness.waitUntil({ false }, timeout: .milliseconds(200))

        #expect(
            harness.sessionActivated,
            "the deferred deactivation tore down a session that play() had already re-activated"
        )
    }
}

#endif
