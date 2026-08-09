//
//  ToggleIntentTests.swift
//  Playback
//
//  `toggle(reason:)` must branch on playback *intent*, not on `isPlaying`.
//
//  The two answer different questions. `isPlaying` asks whether audio is
//  coming out; intent asks whether the listener has asked for audio and not
//  taken it back. They part company for the whole duration of a start that has
//  not yet produced sound — a connect that is buffering, or parked on a dead
//  network. Through that window the button shows pause, because a requested
//  playback is a cancellable one, and a tap must therefore cancel. Branching
//  on `isPlaying` there re-issued `play()` instead: the listener trying to
//  stop a stuck start silently restarted it. Sentry IOS-4K/4M/4N.
//
//  Staleness in the `isPlaying` mirror was the other half of these reports and
//  is fixed at its source — see `PlayerStateMirrorTests`.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
@testable import Playback
@testable import PlaybackCore

@Suite("Toggle Intent Tests")
@MainActor
struct ToggleIntentTests {

    // MARK: - Icon and action agree

    @Test(
        "A tap while a start is still in flight stops it, matching the pause icon",
        arguments: PlayerControllerTestCase.allCases
    )
    func tapDuringInFlightStartStops(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Model a start that has been requested but has produced no audio: the
        // connect is parked or buffering, so no `.playing` ever arrives.
        harness.mockPlayer.shouldAutoUpdateState = false
        try harness.controller.play(reason: .test)
        await harness.waitForAsync()

        #expect(harness.controller.isPlaybackRequested, "the user asked for audio")
        #expect(!harness.controller.isPlaying, "no audio is coming out yet")

        let stopsBeforeTap = harness.mockPlayer.stopCallCount
        try harness.controller.toggle(reason: .test)

        #expect(
            !harness.controller.isPlaybackRequested,
            "the button shows pause while a start is in flight, so the tap must cancel the start"
        )
        #expect(
            harness.mockPlayer.stopCallCount == stopsBeforeTap + 1,
            "cancelling the start must reach the player"
        )
    }

    // MARK: - Errors hand the control back

    @Test(
        "A failed start offers a retry, not a stop",
        arguments: PlayerControllerTestCase.allCases
    )
    func errorOffersRetryNotStop(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // No auto-transition: the start is driven entirely by what this test
        // feeds the player, so the error below is the only state it reaches.
        harness.mockPlayer.shouldAutoUpdateState = false
        try harness.controller.play(reason: .test)
        await harness.waitForAsync()
        #expect(harness.controller.isPlaybackRequested, "precondition: a start was requested")

        harness.mockPlayer.simulateStateChange(to: .error(.connectionFailed("stream unreachable")))
        await harness.waitUntil { harness.controller.state.isError }

        // Intent deliberately survives the error — the analytics/CPU session
        // follows intent rather than individual failures (#512), and the
        // holding pattern reconnects underneath a request that is still
        // standing (#517). So the predicate the *control* renders cannot be
        // raw intent: a failed start has nothing left to cancel, and the only
        // useful thing a tap can do is try again.
        #expect(
            !harness.controller.isPlaybackRequested,
            "an error hands the control back to play so the listener can retry"
        )

        let playsBeforeTap = harness.mockPlayer.playCallCount
        try harness.controller.toggle(reason: .test)

        #expect(
            harness.mockPlayer.playCallCount == playsBeforeTap + 1,
            "the tap must retry the stream, not tear the session down"
        )
    }

    // MARK: - The predicate the button renders

    @Test(
        "isPlaybackRequested tracks intent across a full play/stop cycle",
        arguments: PlayerControllerTestCase.allCases
    )
    func requestedTracksIntent(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        #expect(!harness.controller.isPlaybackRequested)

        try harness.controller.play(reason: .test)
        #expect(harness.controller.isPlaybackRequested)

        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaybackRequested)

        harness.controller.stop(reason: .test)
        await harness.waitUntil { !harness.controller.isPlaybackRequested }
        #expect(!harness.controller.isPlaybackRequested)
    }
}
