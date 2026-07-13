//
//  IntentPlaybackTests.swift
//  WXYCIntents
//
//  Covers the shared poll-until-playback-starts loop that PlayWXYC, ToggleWXYC,
//  and PlayWXYCAudio all rely on to keep their intents alive until the live
//  stream connects. The loop is the previously-duplicated, timeout-prone code;
//  the injectable isPlaying seam lets us exercise it without a live audio session.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYCIntents

@Suite("IntentPlayback wait logic")
@MainActor
struct IntentPlaybackTests {
    @Test("Returns promptly when playback is already underway")
    func returnsWhenAlreadyPlaying() async {
        let clock = ContinuousClock()
        let start = clock.now

        await IntentPlayback.awaitPlaybackStart(
            timeout: .seconds(10),
            context: "test"
        ) { true }

        #expect(clock.now - start < .seconds(1))
    }

    @Test("Returns once playback starts partway through polling")
    func returnsWhenPlaybackStarts() async {
        var polls = 0

        await IntentPlayback.awaitPlaybackStart(
            timeout: .seconds(10),
            context: "test"
        ) {
            polls += 1
            return polls >= 3
        }

        #expect(polls >= 3)
    }

    @Test("Honors the timeout when playback never starts")
    func honorsTimeoutWhenPlaybackNeverStarts() async {
        let clock = ContinuousClock()
        let start = clock.now

        await IntentPlayback.awaitPlaybackStart(
            timeout: .milliseconds(300),
            context: "test"
        ) { false }

        let elapsed = clock.now - start
        #expect(elapsed >= .milliseconds(250))
        #expect(elapsed < .seconds(2))
    }
}
