//
//  StopVersusTearDownTests.swift
//  Playback
//
//  Pins the one difference between `stop(reason:)` and `tearDown(reason:)`,
//  which until the rename were `stopWithAnalytics(reason:)` and
//  `stop(reason:)` — two names that gave a reader no way to tell which one
//  reported a listen, especially since every method on the controller takes a
//  `reason:` documented "(for analytics)" and `play(reason:)` does emit.
//
//  `stop(reason:)` emitting was already covered (`PauseIntentStopEventTests`,
//  `SourceAttributionTests`). The other half never was: nothing asserted that
//  the teardown stays silent, so a capture drifting down into it would have
//  double-counted every interruption and route disconnect — those call
//  `tearDown` precisely because `PlaybackInterruptionRouteHandler` has already
//  filed its own event — and no test would have failed.
//
//  Both tests run the same setup and differ only in which method they call, so
//  the silent one can't pass by observing nothing: its partner proves the
//  harness sees an event from the identical arrangement.
//
//  Created by Jake Bromberg on 08/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
@testable import Playback
@testable import PlaybackCore

#if os(iOS) || os(tvOS)

@Suite("stop(reason:) versus tearDown(reason:)")
@MainActor
struct StopVersusTearDownTests {

    @Test("tearDown ends an active listen without reporting it")
    func tearDownEmitsNothing() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        controller.tearDown(reason: .interruptionBegan)

        #expect(
            harness.analyticsStopCallCount == 0,
            "tearDown must stay silent — PlaybackInterruptionRouteHandler emits its own event before calling it, so a capture here double-counts the listen"
        )
        #expect(!controller.isPlaybackRequested, "tearDown must still tear playback down")
    }

    @Test("stop reports the same listen tearDown ends silently")
    func stopEmitsOne() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let controller = try #require(harness.audioController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        controller.stop(reason: .interruptionBegan)

        #expect(
            harness.analyticsStopCallCount == 1,
            "the identical arrangement does produce an observable event — which is what makes the silence asserted above meaningful"
        )
        #expect(!controller.isPlaybackRequested)
    }
}

#endif
