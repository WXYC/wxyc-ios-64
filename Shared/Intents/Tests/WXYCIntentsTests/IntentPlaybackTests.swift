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

import PlaybackCore
import Testing
@testable import WXYCIntents

@Suite("IntentPlayback wait logic")
@MainActor
struct IntentPlaybackTests {
    @Test("Returns promptly when playback is already underway")
    func returnsWhenAlreadyPlaying() async {
        let clock = ContinuousClock()
        let start = clock.now

        let started = await IntentPlayback.awaitPlaybackStart(
            timeout: .seconds(10),
            context: "test"
        ) { true }

        #expect(started)
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

        let started = await IntentPlayback.awaitPlaybackStart(
            timeout: .milliseconds(300),
            context: "test"
        ) { false }

        let elapsed = clock.now - start
        #expect(!started, "A timed-out wait must report that playback never started")
        #expect(elapsed >= .milliseconds(250))
        #expect(elapsed < .seconds(2))
    }

    @Test("startAndAwait prepares the session, plays with the given reason, and reports success once the injected controller is playing")
    func startAndAwaitReportsSuccessAgainstInjectedController() async {
        let clock = ContinuousClock()
        let start = clock.now
        let controller = FakeIntentPlaybackController()
        controller.isPlaying = true

        let started = await IntentPlayback.startAndAwait(
            reason: .test,
            timeout: .seconds(10),
            controller: controller
        )

        #expect(started)
        #expect(clock.now - start < .seconds(1))
        #expect(controller.prepareForPlaybackCallCount == 1)
        #expect(controller.playedReasons == [.test])
    }

    @Test("startAndAwait honors the timeout when the injected controller never reports playing")
    func startAndAwaitHonorsTimeoutAgainstInjectedController() async {
        let clock = ContinuousClock()
        let start = clock.now
        let controller = FakeIntentPlaybackController()

        let started = await IntentPlayback.startAndAwait(
            reason: .test,
            timeout: .milliseconds(300),
            controller: controller
        )

        let elapsed = clock.now - start
        #expect(!started, "A timed-out wait must report that playback never started")
        #expect(elapsed >= .milliseconds(250))
        #expect(elapsed < .seconds(2))
        // The seam must still start playback -- a timeout means the stream
        // never connected, not that startAndAwait skipped calling play().
        #expect(controller.prepareForPlaybackCallCount == 1)
        #expect(controller.playedReasons == [.test])
    }
}

/// Records `IntentPlaybackControlling` calls and lets a test drive `isPlaying`
/// directly, so `IntentPlayback.startAndAwait(reason:controller:)` -- the
/// path `PlayWXYC`, `PlayWXYCAudio`, and `PlayMediaIntentHandler` all run --
/// can be exercised without touching `AudioPlayerController.shared` or a real
/// audio session. #497: `MockAudioPlayer` (`PlaybackTestUtilities`) isn't
/// importable here because that target isn't a product library; this fake
/// sits at the narrower `IntentPlaybackControlling` boundary the intents
/// actually use. Declared here (not in `PlayWXYCAudioTests.swift`) so it's
/// available regardless of the `#if compiler(>=6.4)` gate that file lives
/// behind.
@MainActor
final class FakeIntentPlaybackController: IntentPlaybackControlling {
    private(set) var prepareForPlaybackCallCount = 0
    private(set) var playedReasons: [PlaybackReason] = []
    var isPlaying = false

    func prepareForPlayback() {
        prepareForPlaybackCallCount += 1
    }

    func play(reason: PlaybackReason) {
        playedReasons.append(reason)
    }
}
