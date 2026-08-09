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
