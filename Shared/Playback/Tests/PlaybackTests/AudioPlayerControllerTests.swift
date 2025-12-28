//
//  AudioPlayerControllerTests.swift
//  PlaybackTests
//
//  Unit tests for AudioPlayerController-specific functionality.
//
//  Note: Common behavior tests (play/stop/toggle, background/foreground, interruption
//  handling, analytics, stall recovery) are now covered by parameterized tests in
//  PlaybackTests/Behavior/ that test both RadioPlayerController and AudioPlayerController.
//
//  This file contains only AudioPlayerController-specific tests:
//  - PlayerType switching
//  - Audio session category configuration
//  - Remote command center configuration
//
    
import Testing
import AVFoundation
@testable import Playback
@testable import PlaybackCore

@Suite("AudioPlayerController Tests")
@MainActor
struct AudioPlayerControllerTests {
    
    #if os(iOS) || os(tvOS)

    // MARK: - PlayerType Tests

    @Test("Controller can change playerType")
    func controllerCanChangePlayerType() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()

        let controller = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        // Default is avAudioStreamer
        #expect(controller.playerType == .avAudioStreamer)

        // Change to radioPlayer
        controller.playerType = .radioPlayer
        #expect(controller.playerType == .radioPlayer)
    }

    // MARK: - Audio Session Tests

    @Test("Audio session is configured on init")
    func audioSessionConfiguredOnInit() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()

        _ = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        // Session category should be set during init
        #expect(mockSession.setCategoryCallCount == 1)
        #expect(mockSession.lastCategory == .playback)
    }

    // MARK: - Remote Command Center Tests

    @Test("Remote commands are configured correctly")
    func remoteCommandsConfigured() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()

        _ = AudioPlayerController(
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
        let controller = AudioPlayerController(
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        // Initial state should be not playing
        #expect(controller.isPlaying == false)
        #expect(controller.isLoading == false)
    }

    #endif
}
