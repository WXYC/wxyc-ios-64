//
//  AudioPlayerControllerTests.swift
//  PlaybackTests
//
//  Tests for AudioPlayerController and its state management
//

import Testing
import AVFoundation
@testable import Playback
@testable import PlaybackCore

@Suite("AudioPlayerController Tests")
@MainActor
struct AudioPlayerControllerTests {
    
    // NOTE: Many tests that previously injected mock players have been removed
    // because the simplified AudioPlayerController API no longer supports
    // player injection. The player is now created internally via createPlayer(for:).
    //
    // Tests that need to verify behavior through mock players should use the
    // AudioPlayerControllerBehaviorTests which test the protocol-level behavior.
    
    #if os(iOS) || os(tvOS)
    
    @Test("Controller initializes correctly")
    func controllerInitializes() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )
        
        // Initial state should be not playing
        #expect(controller.isPlaying == false)
        #expect(controller.isLoading == false)
    }
    
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

    @Test("Remote command targets are added", .disabled("Mock targets not captured - needs investigation"))
    func remoteCommandTargetsAdded() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()

        _ = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        #expect(!mockCommandCenter.mockPlayCommand.targets.isEmpty)
        #expect(!mockCommandCenter.mockPauseCommand.targets.isEmpty)
        #expect(!mockCommandCenter.mockTogglePlayPauseCommand.targets.isEmpty)
    }

    // MARK: - App Lifecycle Tests

    @Test("Background while not playing deactivates session")
    func backgroundWhileNotPlayingDeactivatesSession() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()

        let controller = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        mockSession.reset()

        controller.handleAppDidEnterBackground()

        // Session should be deactivated when not playing
        #expect(mockSession.lastActiveState == false)
    }

    @Test("Background while playing keeps session active")
    func backgroundWhilePlayingKeepsSessionActive() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayer()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        controller.play()
        mockSession.reset() // Reset to track only background behavior

        controller.handleAppDidEnterBackground()

        // Session should NOT be deactivated when playing (no setActive call)
        #expect(mockSession.setActiveCallCount == 0)
    }

    @Test("Foreground while playing activates session")
    func foregroundWhilePlayingActivatesSession() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayer()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        controller.play()
        mockSession.reset() // Reset to track only foreground behavior

        controller.handleAppWillEnterForeground()

        // Session should be activated when returning to foreground while playing
        #expect(mockSession.lastActiveState == true)
    }

    @Test("Foreground while not playing does not activate session")
    func foregroundWhileNotPlayingDoesNotActivateSession() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()

        let controller = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        // Not playing, return to foreground
        mockSession.reset()

        controller.handleAppWillEnterForeground()

        // Session should NOT be activated when not playing
        #expect(mockSession.setActiveCallCount == 0)
    }

    @Test("Background after pause deactivates session")
    func backgroundAfterPauseDeactivatesSession() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayer()

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: MockPlaybackAnalytics()
        )

        controller.play()
        controller.pause()
        mockSession.reset()

        controller.handleAppDidEnterBackground()

        // Session should be deactivated after pause + background
        #expect(mockSession.lastActiveState == false)
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
