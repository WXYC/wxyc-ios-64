//
//  AudioPlayerControllerTests.swift
//  PlaybackTests
//
//  Tests for AudioPlayerController and its state management
//

import Testing
import AVFoundation
@testable import Playback

@Suite("AudioPlayerController Tests")
@MainActor
struct AudioPlayerControllerTests {
    
    // NOTE: Many tests that previously injected mock players have been removed
    // because the simplified AudioPlayerController API no longer supports
    // player injection. The player is now created internally via createPlayer(for:).
    //
    // Tests that need to verify behavior through mock players should use the
    // AudioPlayerControllerBehaviorTests which test the protocol-level behavior.
    
    #if os(iOS) || os(tvOS) || os(watchOS)
    
    @Test("Controller initializes correctly")
    func controllerInitializes() {
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
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
            analytics: nil
        )
        
        // Default is avAudioStreamer
        #expect(controller.playerType == .avAudioStreamer)
        
        // Change to radioPlayer
        controller.playerType = .radioPlayer
        #expect(controller.playerType == .radioPlayer)
    }
    
    #endif
    
    #if os(macOS)
    
    @Test("Controller initializes correctly on macOS")
    func controllerInitializesMacOS() {
        let controller = AudioPlayerController(
            notificationCenter: .default,
            analytics: nil
        )
        
        // Initial state should be not playing
        #expect(controller.isPlaying == false)
        #expect(controller.isLoading == false)
    }
    
    #endif
}
