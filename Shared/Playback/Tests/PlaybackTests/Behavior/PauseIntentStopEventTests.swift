//
//  PauseIntentStopEventTests.swift
//  Playback
//
//  #939: a Siri pause has to close the listen it ends, not just record that
//  Siri was used. `AudioPlayerController.stopWithAnalytics(reason:)` is the
//  one place the "capture a PlaybackStoppedEvent, then stop" rule lives —
//  #933's dedup included — and `PauseWXYC` calling `stop(reason:)` directly
//  bypassed it entirely, so a Siri pause retired the #665 session id with no
//  duration ever recorded on the #663 series. This suite pins the entry
//  point's contract at the controller seam: `PauseWXYC.perform()` itself
//  reaches two hard singletons and isn't reachable from a unit test (see
//  `PauseWXYC.swift`'s header), so the rule is verified here and the intent
//  file only has to be shown to be calling it (grep, not a test).
//
//  Created by Jake Bromberg on 08/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
@testable import Playback
@testable import PlaybackCore

#if os(iOS) || os(tvOS)

@Suite("Pause Intent Stop Event Tests")
@MainActor
struct PauseIntentStopEventTests {

    @Test("A Siri pause on an active listen emits one PlaybackStoppedEvent with a real duration and the live sessionID")
    func siriPauseEmitsOneStoppedEventWithDurationAndSessionID() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        let listenSessionID = try #require(controller.sessionID, "precondition: play() mints a session id")
        try? await Task.sleep(for: .milliseconds(20))

        controller.stopWithAnalytics(reason: .pauseIntent)

        #expect(
            harness.analyticsStopCallCount == 1,
            "expected exactly one PlaybackStoppedEvent for the listen the Siri pause closed"
        )
        let event = harness.mockAnalytics.stoppedEvents.last
        #expect((event?.duration ?? 0) > 0, "a Siri pause must record the listen's real elapsed duration, not zero")
        #expect(event?.sessionID == listenSessionID, "the stopped event must carry the sessionID of the listen it closed")
    }

    @Test("PlaybackReason.pauseIntent reaches the stopped event's source as Siri attribution")
    func pauseIntentAttributesSiri() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        controller.stopWithAnalytics(reason: .pauseIntent)

        #expect(
            harness.mockAnalytics.stoppedEvents.last?.source == PlaybackSource.siri.rawValue,
            "a Siri pause must attribute .siri, not fall through to .unknown"
        )
    }

    @Test("Two Siri pauses in a row emit one PlaybackStoppedEvent, not two (#933)")
    func repeatedSiriPausesEmitOneStoppedEvent() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        controller.stopWithAnalytics(reason: .pauseIntent)
        controller.stopWithAnalytics(reason: .pauseIntent)

        #expect(
            harness.analyticsStopCallCount == 1,
            "a repeated Siri pause double-counted the listen the first pause already closed"
        )
    }

    @Test("A Siri pause against an already-stopped controller emits no PlaybackStoppedEvent")
    func siriPauseAgainstStoppedControllerEmitsNoEvent() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        #expect(controller.debugState.playerState == .idle, "precondition: nothing is playing")

        controller.stopWithAnalytics(reason: .pauseIntent)

        #expect(
            harness.analyticsStopCallCount == 0,
            "a Siri pause against an idle controller must not fabricate a listen to close"
        )
    }
}

#endif
