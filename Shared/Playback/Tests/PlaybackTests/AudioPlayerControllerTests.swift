//
//  AudioPlayerControllerTests.swift
//  Playback
//
//  Unit tests for AudioPlayerController-specific functionality.
//
//  Note: Common behavior tests (play/stop/toggle, background/foreground, interruption
//  handling, analytics, stall recovery) are now covered by parameterized tests in
//  PlaybackTests/Behavior/ that test both RadioPlayerController and AudioPlayerController.
//
//  This file contains only AudioPlayerController-specific tests:
//  - Audio session category configuration
//  - Remote command center configuration
//
//  Created by Jake Bromberg on 12/14/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
import Analytics
import AnalyticsTesting
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import MP3StreamerModule
@testable import HLSPlayerModule
#endif

@Suite("AudioPlayerController Tests")
@MainActor
struct AudioPlayerControllerTests {

    #if os(iOS) || os(tvOS)

    // MARK: - Deferred Audio Session Tests

    @Test("Audio session category is NOT configured on init (deferred)")
    func audioSessionNotConfiguredOnInit() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        _ = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        // Session category should NOT be set during init (deferred until play)
        #expect(mockSession.setCategoryCallCount == 0)
        #expect(mockSession.setActiveCallCount == 0)
    }

    @Test("Audio session category is configured on first play with longFormAudio policy")
    func audioSessionConfiguredOnPlay() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        // Before play - no configuration
        #expect(mockSession.setCategoryCallCount == 0)

        // Play triggers configuration
        controller.play()

        #expect(mockSession.setCategoryCallCount == 1)
        #expect(mockSession.lastCategory == .playback)
        #expect(mockSession.lastPolicy == .longFormAudio)
        #expect(mockSession.setActiveCallCount == 1)
        #expect(mockSession.lastActiveState == true)
    }

    @Test("Audio session category is configured only once across multiple plays")
    func audioSessionConfiguredOnlyOnce() async {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        controller.play()
        controller.stop()
        // stop() hands the session back off its own turn, so the setActive count
        // below is a race with the second play() unless we wait for it: a
        // deactivation that loses is correctly skipped as stale and never calls
        // setActive. Waiting on the handback having *settled* rather than on the
        // mock recording the call — the mock records it while the controller is
        // still holding the session lock, so a play() started then would defer
        // and never activate at all. See PauseResponsivenessTests.
        await waitUntil { !controller.debugState.sessionDeactivationInFlight }
        #expect(mockSession.lastActiveState == false, "precondition: the handback never landed")
        controller.play()

        // Category should only be set once (idempotent)
        #expect(mockSession.setCategoryCallCount == 1)
        // setActive is called: play(true), stop(false), play(true) = 3 times
        #expect(mockSession.setActiveCallCount == 3)
    }

    // MARK: - Audio Session Failure Guard

    @Test("Play keeps intent on a generic activation failure so the startup watchdog can escalate (#518, 6-A)")
    func playKeepsIntentOnSessionActivationFailure() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        mockSession.shouldThrowOnSetActive = true

        controller.play()

        // The player never starts (activation failed), but under #518's 6-A
        // design the non-`'!int'` abort no longer tears intent down: it keeps
        // `playbackIntended` set (so `isLoading` is true) and escalates
        // recovery immediately (`silent_startup` + reconnect ramp) rather than
        // stranding the user in silence.
        #expect(controller.isPlaying == false)
        #expect(controller.isLoading == true)
        #expect(mockPlayer.isPlaying == false)

        // Tear intent down so the escalated recovery loop doesn't keep
        // retrying activation for the remainder of the test process.
        controller.stop(reason: .test)
    }

    // MARK: - Debug Snapshot

    @Test("debugStateSnapshot includes the documented diagnostic fields")
    func debugStateSnapshotIncludesDocumentedFields() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        let snapshot = controller.debugStateSnapshot

        // The snapshot exists so a future CI flake on PlayWXYCIntentTests can be
        // diagnosed without reproducing locally; assert the field names we're
        // committing to so a refactor that drops one is caught.
        for field in ["playerState=", "playbackIntended=", "isPlaying=", "isLoading=", "audioSessionActivated=", "sessionDeactivationInFlight=", "isForegrounded="] {
            #expect(snapshot.contains(field), "debugStateSnapshot missing '\(field)': \(snapshot)")
        }
    }

    // MARK: - Output Latency Tests

    @Test("Output latency returns audio session's output latency")
    func outputLatencyReturnsSessionValue() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        mockSession.outputLatency = 2.0

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        #expect(controller.outputLatency == 2.0)
    }

    @Test("Output latency returns 0 when audio session is nil")
    func outputLatencyReturnsZeroWithNilSession() {
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: nil,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        #expect(controller.outputLatency == 0)
    }

    // MARK: - Double-Count Regression Tests (#669)

    /// `makePlayer(for:)` is what `AudioPlayerController.shared` calls in
    /// production for every player-experiment arm. Before #669, the
    /// `.radioPlayer` and `.hlsPlayer` arms wrapped a player whose OWN
    /// analytics sink defaulted to the real, shared PostHog service, so
    /// `play()` reported "play" twice: once from this controller and once
    /// from the wrapped player. `.mp3Streamer` was never affected — its sink
    /// already defaulted to nil.
    ///
    /// The redundant emission targets the live `StructuredPostHogAnalytics`
    /// singleton, not this test's injected `MockStructuredAnalytics` — so a
    /// `count == 1` assertion against the mock alone can't tell "the
    /// controller emitted once" apart from "the controller emitted once AND
    /// the wrapped player quietly emitted a second, unobserved 'play' to the
    /// real service." The `hasAnalyticsSink` assertion below closes that gap
    /// by inspecting the actual invariant #669 establishes: the wrapped
    /// player must carry no analytics sink at all, so it is structurally
    /// incapable of emitting, regardless of what the controller's own sink
    /// happens to be. Together the two assertions pin "controller emits
    /// exactly one, wrapped player emits none."
    @Test(
        "makePlayer wires every experiment arm with a nil-analytics wrapped player, so the controller alone emits exactly one play event (#669)",
        arguments: PlayerControllerType.allCases
    )
    func makePlayerNeverDoubleCountsPlay(type: PlayerControllerType) throws {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockAnalytics = MockStructuredAnalytics()

        let player = AudioPlayerController.makePlayer(for: type)

        switch type {
        case .mp3Streamer:
            let mp3Streamer = try #require(player as? MP3Streamer, "makePlayer(for: .mp3Streamer) should return an MP3Streamer")
            #expect(mp3Streamer.hasAnalyticsSink == false, "MP3Streamer must carry no analytics sink — the controller is the sole emitter")
        case .radioPlayer:
            let radioPlayer = try #require(player as? RadioPlayer, "makePlayer(for: .radioPlayer) should return a RadioPlayer")
            #expect(radioPlayer.hasAnalyticsSink == false, "RadioPlayer must carry no analytics sink — the controller is the sole emitter")
        case .hlsPlayer:
            let hlsPlayer = try #require(player as? HLSPlayer, "makePlayer(for: .hlsPlayer) should return an HLSPlayer")
            #expect(hlsPlayer.hasAnalyticsSink == false, "HLSPlayer must carry no analytics sink — the controller is the sole emitter")
        }

        let controller = AudioPlayerController(
            player: player,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: mockAnalytics
        )

        controller.play(reason: .test)

        #expect(
            mockAnalytics.startedEvents.count == 1,
            "\(type.rawValue) produced \(mockAnalytics.startedEvents.count) play events, expected 1"
        )

        controller.stop(reason: .test)
    }

    // MARK: - Remote Command Center Tests

    @Test("Remote commands are configured correctly")
    func remoteCommandsConfigured() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        _ = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        #expect(mockCommandCenter.playCommand.isEnabled)
        #expect(mockCommandCenter.pauseCommand.isEnabled)
        #expect(mockCommandCenter.togglePlayPauseCommand.isEnabled)
        #expect(!mockCommandCenter.stopCommand.isEnabled)
        #expect(!mockCommandCenter.skipForwardCommand.isEnabled)
        #expect(!mockCommandCenter.skipBackwardCommand.isEnabled)
    }

    #endif

    #if os(macOS)

    @Test("Controller initializes correctly on macOS")
    func controllerInitializesMacOS() {
        let mockPlayer = MockAudioPlayerForController()
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        // Initial state should be not playing
        #expect(controller.isPlaying == false)
        #expect(controller.isLoading == false)
    }

    #endif
}

// MARK: - Mock Player for Tests

/// Simple mock player that satisfies AudioPlayerProtocol for controller tests.
/// Named differently to avoid conflict with MockPlayer in PlaybackTestUtilities.
final class MockAudioPlayerForController: AudioPlayerProtocol, @unchecked Sendable {
    var state: PlayerState = .idle
    var isPlaying: Bool = false

    var stateStream: AsyncStream<PlayerState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    var eventStream: AsyncStream<AudioPlayerInternalEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { $0.finish() }
    }

    func play() {
        isPlaying = true
        state = .playing
    }

    func stop() {
        isPlaying = false
        state = .idle
    }

    func installRenderTap() {}
    func removeRenderTap() {}
}

// MARK: - Test Helpers

/// Polls until `condition` holds or the timeout expires.
///
/// `AudioPlayerController` hands the audio session back off the caller's turn,
/// so a test that counts `setActive` calls has to wait for the deactivation
/// rather than read the count inline. The suites built on
/// `PlayerControllerTestHarness` use its `waitUntil`; these tests construct a
/// controller directly, so they need their own.
@MainActor
private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(1)) async {
    let deadline = ContinuousClock().now + timeout
    while !condition(), ContinuousClock().now < deadline {
        await Task.yield()
    }
}
