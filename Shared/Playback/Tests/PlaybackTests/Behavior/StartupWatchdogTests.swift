//
//  StartupWatchdogTests.swift
//  Playback
//
//  Behavior tests for the controller-level play-intent → first-audio watchdog
//  (#518). The fully-silent startup class — Sentry IOS-31 (iOS 27) and IOS-35
//  (Mac Catalyst) — is `play()` called, audio never arriving, and zero playback
//  telemetry: no `first_audio`, no `stream_error`, no `stall_recovery`. The
//  watchdog makes that class visible (`silent_startup`) and self-healing (drives
//  the existing ramp→holding recovery). See the #509 playback-reliability
//  tracker; sibling #487 (MP3Streamer-layer watchdog), disarm keyed off #513
//  (`firstAudio`).
//
//  Created by Jake Bromberg on 07/15/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
import Core
import Analytics
import AnalyticsTesting
@testable import Playback
@testable import PlaybackCore

#if !os(watchOS)

#if os(iOS)
/// Reproduces the `'!int'` `CannotInterruptOthers` NSError so the deferred-retry
/// path can be exercised deterministically (mirrors `SessionActivationRetryTests`).
@MainActor
private func cannotInterruptOthersError() -> NSError {
    NSError(
        domain: "com.apple.coreaudio.avfaudio",
        code: Int(AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue)
    )
}
#endif

/// Drives a real `AudioPlayerController` with a mock player + session, injecting
/// a short `startupWatchdogDeadline` so the watchdog fires quickly and
/// deterministically. Built without the parameterized harness because
/// `audioPlayerController` isn't a `PlayerControllerTestCase` on macOS and these
/// are AudioPlayerController-specific.
@Suite("Startup Watchdog Tests")
@MainActor
struct StartupWatchdogTests {

    // MARK: - Fixture

    private struct Fixture {
        let controller: AudioPlayerController
        let mockPlayer: MockAudioPlayer
        let mockSession: MockAudioSession
        let mockAnalytics: MockStructuredAnalytics
    }

    private static func makeFixture(
        deadline: Duration = .milliseconds(150),
        backoff: ExponentialBackoff = .default
    ) -> Fixture {
        let mockPlayer = MockAudioPlayer(url: URL(string: "https://example.com/stream")!)
        // The fully-silent class is exactly "play() called, player never reports
        // .playing". Auto-update would report .playing immediately and disarm the
        // watchdog, so tests drive state explicitly.
        mockPlayer.shouldAutoUpdateState = false
        let mockSession = MockAudioSession()
        let mockAnalytics = MockStructuredAnalytics()
        let notificationCenter = NotificationCenter()

        #if os(iOS) || os(tvOS)
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: notificationCenter,
            analytics: mockAnalytics,
            backoffTimer: backoff,
            startupWatchdogDeadline: deadline
        )
        #else
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: notificationCenter,
            analytics: mockAnalytics,
            backoffTimer: backoff,
            startupWatchdogDeadline: deadline
        )
        #endif

        return Fixture(
            controller: controller,
            mockPlayer: mockPlayer,
            mockSession: mockSession,
            mockAnalytics: mockAnalytics
        )
    }

    // MARK: - Helpers

    private static func silentStartupEvents(_ fixture: Fixture) -> [StreamErrorEvent] {
        fixture.mockAnalytics.events
            .compactMap { $0 as? StreamErrorEvent }
            .filter { $0.errorType == .silentStartup }
    }

    /// Drains queued MainActor work (the event/state observer tasks) so a
    /// disarm signal is fully processed before we probe.
    private static func drain() async {
        for _ in 0..<32 {
            await Task.yield()
        }
    }

    /// Polls a MainActor condition up to a wall-clock deadline.
    private static func poll(
        until condition: @MainActor () -> Bool,
        timeout: Duration = .seconds(2)
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline, !condition() {
            await Task.yield()
        }
    }

    // MARK: - Test 1: silent start escalates

    @Test(
        "A silent start emits exactly one silent_startup event and drives a recovery attempt",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
    func silentStartEscalates() async {
        let fixture = Self.makeFixture()

        fixture.controller.play(reason: .test)

        // The watchdog fires after the deadline; its escalation re-invokes
        // player.play() (playCallCount: 1 initial + 1 recovery).
        await Self.poll(until: {
            !Self.silentStartupEvents(fixture).isEmpty && fixture.mockPlayer.playCallCount >= 2
        })

        #expect(Self.silentStartupEvents(fixture).count == 1)
        #expect(fixture.mockPlayer.playCallCount >= 2)

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 2: first-audio disarms

    @Test("first_audio before the deadline disarms the watchdog")
    func firstAudioDisarms() async {
        let fixture = Self.makeFixture()

        fixture.controller.play(reason: .test)
        fixture.mockPlayer.simulateFirstAudio()
        await Self.drain()

        // Wait well past the deadline; a disarmed watchdog must not fire.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(Self.silentStartupEvents(fixture).isEmpty)

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 3: reaching .playing disarms (non-MP3Streamer path)

    @Test("A start that reaches .playing then stalls before the deadline does not misfire silent_startup")
    func playingThenStallDoesNotMisfire() async {
        // Deadline long enough to sequence play → playing → stall inside it —
        // with margin for a loaded CI machine, since a late disarm past the
        // deadline would flake — so a lazy `!isPlaying`-only guard would
        // (wrongly) fire at the deadline. The proactive `.playing` disarm must
        // prevent that.
        let fixture = Self.makeFixture(deadline: .seconds(1))

        fixture.controller.play(reason: .test)
        // RadioPlayer/HLS reach .playing without ever emitting `.firstAudio`.
        fixture.mockPlayer.simulateStateChange(to: .playing)
        await Self.poll(until: { fixture.controller.isPlaying }, timeout: .milliseconds(300))

        // Now stall (isPlaying → false) while the watchdog window is still open.
        fixture.mockPlayer.simulateStateChange(to: .stalled)
        await Self.poll(until: { !fixture.controller.isPlaying }, timeout: .milliseconds(300))

        // Past the deadline: a stall after a healthy start is the `.stall`
        // reconnect path's job, not a silent start.
        try? await Task.sleep(for: .milliseconds(1100))

        #expect(Self.silentStartupEvents(fixture).isEmpty)

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 4: error disarms (dedup vs the inner startup_timeout class)

    @Test("An error before the deadline disarms the watchdog (no double count)")
    func errorDisarms() async {
        let fixture = Self.makeFixture()

        fixture.controller.play(reason: .test)
        fixture.mockPlayer.simulateError(TestStreamError.networkFailure)
        await Self.drain()

        try? await Task.sleep(for: .milliseconds(300))

        // The `.error` produced its own StreamErrorEvent; the watchdog must not
        // pile a `silent_startup` on top for the same failed start.
        #expect(Self.silentStartupEvents(fixture).isEmpty)

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 5: stop disarms

    @Test("stop before the deadline disarms the watchdog")
    func stopDisarms() async {
        let fixture = Self.makeFixture()

        fixture.controller.play(reason: .test)
        fixture.controller.stop(reason: .test)

        try? await Task.sleep(for: .milliseconds(300))

        #expect(Self.silentStartupEvents(fixture).isEmpty)
    }

    // MARK: - Test 6: non-'!int' activation abort escalates immediately (6-A)

    #if os(iOS) || os(tvOS)
    @Test(
        "A non-'!int' activation abort escalates immediately — no watchdog wait — and the retry recovers",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
    func nonInterruptAbortEscalates() async {
        // Deadline far beyond the poll window: only an immediate, synchronous
        // escalation (not a watchdog fire) can produce the event in time. The
        // failure is known synchronously at play(), so the user must not spend
        // the whole intent→audio deadline staring at a dead spinner.
        let fixture = Self.makeFixture(deadline: .seconds(30))

        // First activation fails with a generic (non-'!int') error; the
        // escalation's re-activation succeeds and reaches player.play().
        fixture.mockSession.failSetActiveCount = 1
        fixture.mockSession.setActiveError = TestStreamError.playerFailure

        fixture.controller.play(reason: .test)

        await Self.poll(until: {
            !Self.silentStartupEvents(fixture).isEmpty && fixture.mockPlayer.playCallCount >= 1
        })

        #expect(Self.silentStartupEvents(fixture).count == 1)
        // The initial play aborted before player.play(); the recovery's
        // successful re-activation is what reaches it.
        #expect(fixture.mockPlayer.playCallCount >= 1)

        fixture.controller.stop(reason: .test)
    }
    #endif

    // MARK: - Test 7: '!int' retries exhausting leaves intent set

    #if os(iOS)
    @Test(
        "When '!int' retries exhaust, playbackIntended stays true so the armed watchdog remains live",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
    func interruptExhaustionKeepsIntent() async {
        // A long deadline so the watchdog doesn't fire during this invariant
        // check — we're asserting the state the watchdog depends on, not its fire.
        let fixture = Self.makeFixture(deadline: .seconds(30))
        fixture.mockSession.shouldThrowOnSetActive = true
        fixture.mockSession.setActiveError = cannotInterruptOthersError()

        fixture.controller.play(reason: .test)

        // 1 initial activation + maxSessionActivationRetries (4) = 5 attempts.
        await Self.poll(until: { fixture.mockSession.setActiveCallCount >= 5 }, timeout: .seconds(3))

        #expect(fixture.mockSession.setActiveCallCount >= 5)
        #expect(fixture.controller.debugStateSnapshot.contains("playbackIntended=true"))

        fixture.controller.stop(reason: .test)
    }
    #endif

    // MARK: - Test 8: escalation survives persistent re-activation failure

    #if os(iOS) || os(tvOS)
    @Test(
        "Escalation stays on the ramp while re-activation keeps failing, and plays once it clears",
        .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
    )
    func escalationSurvivesPersistentActivationFailure() async {
        // A fast ramp so repeated activation-failed attempts resolve quickly;
        // maximumWaitTime caps the backoff's up-to-1s random jitter per attempt.
        let fixture = Self.makeFixture(
            backoff: ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.05, maximumAttempts: 10)
        )
        // The initial play() and the escalation's first three ramp re-activations
        // fail with a generic (non-'!int') error; the fifth activation succeeds.
        // A ramp that aborts on its first failed re-activation would plateau at
        // setActiveCallCount == 2 and never reach player.play(), re-stranding
        // the silent-startup class this watchdog exists to heal.
        fixture.mockSession.failSetActiveCount = 4

        fixture.controller.play(reason: .test)

        await Self.poll(until: { fixture.mockPlayer.playCallCount >= 1 })

        #expect(Self.silentStartupEvents(fixture).count == 1)
        #expect(fixture.mockSession.setActiveCallCount >= 5)
        #expect(fixture.mockPlayer.playCallCount >= 1)

        fixture.controller.stop(reason: .test)
    }
    #endif

    // MARK: - Test 9: mirror lag at the deadline boundary does not misfire

    @Test("A .playing the state mirror hasn't processed yet does not misfire silent_startup")
    func mirrorLagDoesNotMisfire() async {
        let fixture = Self.makeFixture()

        fixture.controller.play(reason: .test)
        // Put the player in .playing WITHOUT yielding to stateStream — the
        // controller's mirrored state stays stale, modeling first audio landing
        // in the narrow window between the deadline elapsing and the state
        // observer catching up. The fire guard must consult the live player,
        // not just the mirror, so this near-miss can't pollute the
        // silent_startup fleet metric (#509) with a spurious event.
        fixture.mockPlayer.state = .playing
        fixture.mockPlayer.isPlaying = true

        // Wait well past the deadline; the watchdog must not fire.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(Self.silentStartupEvents(fixture).isEmpty)

        fixture.controller.stop(reason: .test)
    }
}

#endif
