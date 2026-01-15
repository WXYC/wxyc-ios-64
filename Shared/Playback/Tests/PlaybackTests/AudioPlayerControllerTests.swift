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
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule

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
            analytics: MockPlaybackAnalytics()
        )

        // Session category should NOT be set during init (deferred until play)
        #expect(mockSession.setCategoryCallCount == 0)
        #expect(mockSession.setActiveCallCount == 0)
    }

    @Test("Audio session category is configured on first play")
    func audioSessionConfiguredOnPlay() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        // Before play - no configuration
        #expect(mockSession.setCategoryCallCount == 0)

        // Play triggers configuration
        controller.play()

        #expect(mockSession.setCategoryCallCount == 1)
        #expect(mockSession.lastCategory == .playback)
        #expect(mockSession.setActiveCallCount == 1)
        #expect(mockSession.lastActiveState == true)
    }

    @Test("Audio session category is configured only once across multiple plays")
    func audioSessionConfiguredOnlyOnce() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayerForController()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        controller.play()
        controller.stop()
        controller.play()

        // Category should only be set once (idempotent)
        #expect(mockSession.setCategoryCallCount == 1)
        // setActive is called: play(true), stop(false), play(true) = 3 times
        #expect(mockSession.setActiveCallCount == 3)
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
            analytics: MockPlaybackAnalytics()
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
            analytics: MockPlaybackAnalytics()
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

    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            continuation.finish()
        }
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
