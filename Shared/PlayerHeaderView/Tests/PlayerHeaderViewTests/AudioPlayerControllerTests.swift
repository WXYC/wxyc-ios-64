//
//  AudioPlayerControllerTests.swift
//  PlayerHeaderViewTests
//
//  Tests for AudioPlayerController with mock dependencies
//

import Testing
import AVFoundation
#if os(iOS)
import UIKit
#endif
@testable import Playback

#if os(iOS) || os(tvOS) || os(watchOS)

@Suite("AudioPlayerController Tests (iOS)")
@MainActor
struct AudioPlayerControllerTests {
    
    let mockPlayer: MockAudioPlayer
    let mockSession: MockAudioSession
    let mockCommandCenter: MockRemoteCommandCenter
    let controller: AudioPlayerController
    
    init() {
        mockPlayer = MockAudioPlayer()
        mockSession = MockAudioSession()
        mockCommandCenter = MockRemoteCommandCenter()
        
        controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default
        )
    }
    
    // MARK: - Playback Tests
    
    @Test("play(url:) starts playback")
    func playWithURL() {
        let url = URL(string: "https://example.com/stream")!
        
        controller.play(url: url)
        
        #expect(mockPlayer.playCallCount == 1)
        #expect(mockPlayer.lastPlayedURL == url)
        #expect(mockPlayer.isPlaying)
    }
    
    @Test("pause() pauses playback")
    func pause() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.pause()
        
        #expect(mockPlayer.pauseCallCount == 1)
        #expect(!mockPlayer.isPlaying)
    }
    
    @Test("toggle() from stopped resumes playback")
    func toggleFromStopped() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        mockPlayer.pause() // Simulate paused state
        
        controller.toggle()
        
        #expect(mockPlayer.resumeCallCount == 1)
    }
    
    @Test("toggle() from playing pauses playback")
    func toggleFromPlaying() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.toggle()
        
        #expect(mockPlayer.pauseCallCount == 1)
    }
    
    @Test("stop() stops playback")
    func stop() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.stop()
        
        #expect(mockPlayer.stopCallCount == 1)
        #expect(!mockPlayer.isPlaying)
    }
    
    // MARK: - Audio Session Tests
    
    @Test("Audio session is configured on init")
    func audioSessionConfiguredOnInit() {
        // Session category should be set during init
        #expect(mockSession.setCategoryCallCount == 1)
        #expect(mockSession.lastCategory == .playback)
    }
    
    @Test("Audio session is activated on play")
    func audioSessionActivatedOnPlay() {
        let url = URL(string: "https://example.com/stream")!
        
        controller.play(url: url)
        
        #expect(mockSession.setActiveCallCount == 1)
        #expect(mockSession.lastActiveState == true)
    }
    
    @Test("Audio session is deactivated on stop")
    func audioSessionDeactivatedOnStop() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.stop()
        
        #expect(mockSession.setActiveCallCount == 2) // Once for play, once for stop
        #expect(mockSession.lastActiveState == false)
    }
    
    // MARK: - Remote Command Center Tests
    
    @Test("Remote commands are configured correctly")
    func remoteCommandsConfigured() {
        #expect(mockCommandCenter.playCommand.isEnabled)
        #expect(mockCommandCenter.pauseCommand.isEnabled)
        #expect(mockCommandCenter.togglePlayPauseCommand.isEnabled)
        #expect(!mockCommandCenter.stopCommand.isEnabled)
        #expect(!mockCommandCenter.skipForwardCommand.isEnabled)
        #expect(!mockCommandCenter.skipBackwardCommand.isEnabled)
    }
    
    @Test("Remote command targets are added")
    func remoteCommandTargetsAdded() {
        #expect(!mockCommandCenter.mockPlayCommand.targets.isEmpty)
        #expect(!mockCommandCenter.mockPauseCommand.targets.isEmpty)
        #expect(!mockCommandCenter.mockTogglePlayPauseCommand.targets.isEmpty)
    }
    
    // MARK: - IsPlaying State Tests
    
    @Test("isPlaying reflects player state")
    func isPlayingReflectsPlayerState() {
        #expect(!controller.isPlaying)
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        #expect(controller.isPlaying)
        
        controller.pause()
        
        #expect(!controller.isPlaying)
    }
    
    // MARK: - Callback Tests
    
    @Test("setAudioBufferHandler receives buffers")
    func setAudioBufferHandler() {
        var receivedBuffer: AVAudioPCMBuffer?
        
        controller.setAudioBufferHandler { buffer in
            receivedBuffer = buffer
        }
        
        // Create a mock buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        
        mockPlayer.simulateAudioBuffer(buffer)
        
        #expect(receivedBuffer != nil)
    }
    
    @Test("setMetadataHandler receives metadata")
    func setMetadataHandler() {
        var receivedMetadata: [String: String]?
        
        controller.setMetadataHandler { metadata in
            receivedMetadata = metadata
        }
        
        let testMetadata = ["StreamTitle": "Test Song"]
        mockPlayer.simulateMetadata(testMetadata)
        
        #expect(receivedMetadata?["StreamTitle"] == "Test Song")
    }
    
    // MARK: - App Lifecycle Tests (iOS only)
    // These tests verify the public lifecycle methods that should be called
    // from SwiftUI's scenePhase handler
    
    #if os(iOS)
    @Test("Background while not playing deactivates session")
    func backgroundWhileNotPlayingDeactivatesSession() {
        mockSession.reset()
        
        controller.handleAppDidEnterBackground()
        
        // Session should be deactivated when not playing
        #expect(mockSession.lastActiveState == false)
    }
    
    @Test("Background while playing keeps session active")
    func backgroundWhilePlayingKeepsSessionActive() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        mockSession.reset() // Reset to track only background behavior
        
        controller.handleAppDidEnterBackground()
        
        // Session should NOT be deactivated when playing (no setActive call)
        #expect(mockSession.setActiveCallCount == 0)
    }
    
    @Test("Foreground while playing activates session")
    func foregroundWhilePlayingActivatesSession() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        mockSession.reset() // Reset to track only foreground behavior
        
        controller.handleAppWillEnterForeground()
        
        // Session should be activated when returning to foreground while playing
        #expect(mockSession.lastActiveState == true)
    }
    
    @Test("Foreground while not playing does not activate session")
    func foregroundWhileNotPlayingDoesNotActivateSession() {
        // Not playing, return to foreground
        mockSession.reset()
        
        controller.handleAppWillEnterForeground()
        
        // Session should NOT be activated when not playing
        #expect(mockSession.setActiveCallCount == 0)
    }
    
    @Test("Rapid background/foreground transitions remain stable")
    func rapidBackgroundForegroundTransitions() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Rapidly cycle between background and foreground
        for _ in 0..<10 {
            controller.handleAppDidEnterBackground()
            controller.handleAppWillEnterForeground()
        }
        
        // Should still be playing and session should be active
        #expect(controller.isPlaying)
        #expect(mockSession.lastActiveState == true)
    }
    
    @Test("Background after pause deactivates session")
    func backgroundAfterPauseDeactivatesSession() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        controller.pause()
        mockSession.reset()
        
        controller.handleAppDidEnterBackground()
        
        // Session should be deactivated after pause + background
        #expect(mockSession.lastActiveState == false)
    }
    #endif
}

#else

// macOS tests - simplified without audio session/remote commands
@Suite("AudioPlayerController Tests (macOS)")
@MainActor
struct AudioPlayerControllerTests {
    
    let mockPlayer: MockAudioPlayer
    let controller: AudioPlayerController
    
    init() {
        mockPlayer = MockAudioPlayer()
        controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default
        )
    }
    
    // MARK: - Playback Tests
    
    @Test("play(url:) starts playback")
    func playWithURL() {
        let url = URL(string: "https://example.com/stream")!
        
        controller.play(url: url)
        
        #expect(mockPlayer.playCallCount == 1)
        #expect(mockPlayer.lastPlayedURL == url)
        #expect(mockPlayer.isPlaying)
    }
    
    @Test("pause() pauses playback")
    func pause() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.pause()
        
        #expect(mockPlayer.pauseCallCount == 1)
        #expect(!mockPlayer.isPlaying)
    }
    
    @Test("toggle() from playing pauses playback")
    func toggleFromPlaying() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.toggle()
        
        #expect(mockPlayer.pauseCallCount == 1)
    }
    
    @Test("stop() stops playback")
    func stop() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.stop()
        
        #expect(mockPlayer.stopCallCount == 1)
        #expect(!mockPlayer.isPlaying)
    }
    
    @Test("isPlaying reflects player state")
    func isPlayingReflectsPlayerState() {
        #expect(!controller.isPlaying)
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        #expect(controller.isPlaying)
        
        controller.pause()
        
        #expect(!controller.isPlaying)
    }
}

#endif
