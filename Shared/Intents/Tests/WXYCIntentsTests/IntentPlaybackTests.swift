//
//  IntentPlaybackTests.swift
//  WXYCIntents
//
//  Covers the shared poll-until-playback-starts loop that PlayWXYC, ToggleWXYC,
//  and PlayWXYCAudio all rely on to keep their intents alive until the live
//  stream connects. The loop is the previously-duplicated, timeout-prone code;
//  the injectable isPlaying seam lets us exercise it without a live audio session.
//
//  Also covers `toggleAndAwait`, the prepare/capture/toggle/wait sequence that
//  `ToggleWXYC` and `WidgetToggleWXYC` were independently reimplementing
//  byte-for-byte (#331). Its pre-toggle predicate is `isPlaybackRequested`, not
//  `isPlaying` — the same predicate `AudioPlayerController.toggle(reason:)`
//  branches on (see `readsPlaybackRequestedNotIsPlayingAsThePreToggleProbe`
//  below), so an in-flight start no longer makes the wait misjudge which way
//  the toggle went.
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
/// directly, so `IntentPlayback.startAndAwait(reason:controller:)` and
/// `toggleAndAwait(reason:context:)` -- the paths every playback intent runs --
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
    private(set) var toggledReasons: [PlaybackReason] = []
    /// Ordered record of the mutating calls, for sequence assertions.
    private(set) var events: [String] = []
    /// How many times `isPlaying` was read — the toggle tests assert on this
    /// to prove the wait branch was (or wasn't) taken.
    private(set) var isPlayingPollCount = 0
    /// Runs after a `toggle(reason:)` is recorded, so a test can model the
    /// toggle's side effect (e.g. flipping `isPlaying` on).
    var onToggle: (@MainActor () -> Void)?
    var isPlaybackRequested = false

    private var isPlayingValue = false
    var isPlaying: Bool {
        get {
            isPlayingPollCount += 1
            return isPlayingValue
        }
        set { isPlayingValue = newValue }
    }

    func prepareForPlayback() {
        prepareForPlaybackCallCount += 1
        events.append("prepare")
    }

    func play(reason: PlaybackReason) {
        playedReasons.append(reason)
        events.append("play")
    }

    func toggle(reason: PlaybackReason) {
        toggledReasons.append(reason)
        events.append("toggle")
        onToggle?()
    }
}

@Suite("IntentPlayback toggleAndAwait")
@MainActor
struct IntentPlaybackToggleAndAwaitTests {
    @Test("Prepares the audio session before toggling")
    func preparesBeforeToggling() async {
        let controller = FakeIntentPlaybackController()
        controller.isPlaybackRequested = true

        await IntentPlayback.toggleAndAwait(
            reason: .testToggle,
            context: "test",
            controller: controller
        )

        #expect(controller.events == ["prepare", "toggle"])
    }

    @Test("Passes the given reason through to toggle")
    func passesReasonToToggle() async {
        let controller = FakeIntentPlaybackController()
        controller.isPlaybackRequested = true

        await IntentPlayback.toggleAndAwait(
            reason: .widgetToggle,
            context: "test",
            controller: controller
        )

        #expect(controller.toggledReasons == [.widgetToggle])
    }

    @Test("Skips the wait when playback was already requested before the toggle")
    func skipsWaitWhenAlreadyRequested() async {
        let controller = FakeIntentPlaybackController()
        controller.isPlaybackRequested = true
        controller.isPlaying = true

        await IntentPlayback.toggleAndAwait(
            reason: .testToggle,
            context: "test",
            controller: controller
        )

        // Since playback was already requested, toggling is turning it off,
        // so there's nothing to wait for — isPlaying should never be polled.
        #expect(controller.isPlayingPollCount == 0)
    }

    @Test("Waits for playback to start when it was not already requested before the toggle")
    func waitsWhenNotAlreadyRequested() async {
        let controller = FakeIntentPlaybackController()
        controller.isPlaybackRequested = false
        controller.onToggle = { [weak controller] in controller?.isPlaying = true }

        await IntentPlayback.toggleAndAwait(
            reason: .testToggle,
            context: "test",
            controller: controller
        )

        // Post-toggle poll: isPlaying reports true immediately, so
        // awaitPlaybackStart's loop exits on its first check.
        #expect(controller.isPlayingPollCount == 1)
    }

    @Test("Reads isPlaybackRequested, not isPlaying, as the pre-toggle probe")
    func readsPlaybackRequestedNotIsPlayingAsThePreToggleProbe() async {
        // Models a start that has been requested but has produced no audio yet
        // (a buffering connect, or one parked on a dead network): isPlaying is
        // still false, but isPlaybackRequested is already true — exactly the
        // predicate `AudioPlayerController.toggle(reason:)` branches on. A tap
        // in this window must cancel the in-flight start, not wait out the
        // full timeout for audio that the toggle just stopped.
        //
        // A buggy implementation that reads `isPlaying` (false) instead of
        // `isPlaybackRequested` (true) as the pre-toggle probe would conclude
        // playback was *not* requested, fail to skip the wait, and poll
        // isPlaying at least once. The correct implementation never polls it.
        let controller = FakeIntentPlaybackController()
        controller.isPlaybackRequested = true
        controller.isPlaying = false

        await IntentPlayback.toggleAndAwait(
            reason: .testToggle,
            context: "test",
            timeout: .milliseconds(200),
            controller: controller
        )

        #expect(controller.isPlayingPollCount == 0)
    }
}
