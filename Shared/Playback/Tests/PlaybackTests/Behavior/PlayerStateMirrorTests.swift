//
//  PlayerStateMirrorTests.swift
//  Playback
//
//  `AudioPlayerController.isPlaying` reads a stored `playerState` mirror rather
//  than the player, so that the Observation framework can track it. The mirror
//  has two writers: `play()`/`stop()` write it synchronously (precisely because
//  the stream lags), and the `player.stateStream` observer writes whatever it
//  is handed. Nothing stopped the async writer from clobbering a newer
//  synchronous one, so a `.playing` emitted before a stop could land after it
//  and leave the mirror claiming playback while the player sat idle.
//
//  Every reader then had to defend itself — `retrySessionActivation()` and
//  `armStartupWatchdog()` both carry a guard for this. These tests pin the
//  invariant at the writer instead: the mirror may not claim playback that no
//  one asked for.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
@testable import Playback
@testable import PlaybackCore

// Scoped to `AudioPlayerController`: `RadioPlayerController.isPlaying` reads
// its live player, so the divergence these tests construct can't arise there.
// Its `state` *is* a stored mirror with the same async writer and no tiebreak,
// so the same staleness is reachable through that property — untested here, and
// the reason `isPlaybackRequested` on that controller reads `state` rather than
// trusting it blindly.
#if os(iOS) || os(tvOS)
@Suite("Player State Mirror Tests")
@MainActor
struct PlayerStateMirrorTests {

    @Test("A .playing delivered after a stop must not resurrect the mirror")
    func stalePlayingIsDropped() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        try harness.controller.play(reason: .test)
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "precondition: the mirror tracks a genuine start")

        harness.controller.stop(reason: .test)
        await harness.waitUntil { !harness.controller.isPlaying }

        // A `.playing` emitted before the stop, delivered after it. The player
        // itself is idle; only the stream is behind.
        harness.mockPlayer.simulateLateStateDelivery(.playing)
        await harness.waitForAsync()

        #expect(!harness.mockPlayer.isPlaying, "precondition: the player really is stopped")
        #expect(
            !harness.controller.isPlaying,
            "the mirror must not report playback the player is not doing"
        )
    }

    @Test("Dropping a stale .playing does not deafen the observer to later states")
    func observerStaysLiveAfterDroppingAStalePlaying() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        try harness.controller.play(reason: .test)
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop(reason: .test)
        await harness.waitUntil { !harness.controller.isPlaying }

        harness.mockPlayer.simulateLateStateDelivery(.playing)
        // `.stalled` is not filtered, so seeing it proves the observer is still
        // consuming the stream — without this, the assertion above could pass
        // merely because nothing was being delivered at all.
        harness.mockPlayer.simulateLateStateDelivery(.stalled)

        await harness.waitUntil { harness.controller.state == .stalled }
        #expect(harness.controller.state == .stalled, "the filter must be narrow, not a mute")
    }

    @Test("A .playing that arrives while a play request is standing is kept")
    func liveplayingIsKept() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // The stream must be the *only* way `.playing` can reach the mirror, or
        // this proves nothing. Left on, the mock's auto-transition sets its own
        // state to `.playing` inside `play()`, and `startPlayerAfterActivation`
        // copies that across synchronously — the mirror would already say
        // `.playing` before the delivery under test, and a guard that rejected
        // every `.playing` (silencing playback in production) would still pass
        // here.
        harness.mockPlayer.shouldAutoUpdateState = false

        // The ordinary path: intent is standing, so the mirror must follow the
        // player. A guard that rejected this would silence playback entirely.
        try harness.controller.play(reason: .test)
        #expect(!harness.controller.isPlaying, "precondition: only the stream can set the mirror")

        harness.mockPlayer.simulateLateStateDelivery(.playing)

        await harness.waitUntil { harness.controller.isPlaying }
        #expect(harness.controller.isPlaying, "a live .playing must reach the mirror")
    }
}
#endif
