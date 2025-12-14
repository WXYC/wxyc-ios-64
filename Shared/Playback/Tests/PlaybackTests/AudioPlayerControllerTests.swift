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
    
    #if os(iOS) || os(tvOS) || os(watchOS)
    
    @Test("Play with URL starts playback")
    func playWithURL() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        // Ensure auto updates are on for basic tests
        mockPlayer.shouldAutoUpdateState = true
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        #expect(mockPlayer.playCallCount == 1)
        #expect(mockPlayer.lastPlayedURL == url)
        #expect(mockPlayer.isPlaying == true)
    }
    
    @Test("Pause stops playback")
    func pause() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        mockPlayer.shouldAutoUpdateState = true
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        controller.pause()
        
        #expect(mockPlayer.pauseCallCount == 1)
        #expect(mockPlayer.isPlaying == false)
    }
    
    @Test("Toggle from playing pauses")
    func toggleFromPlaying() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        mockPlayer.shouldAutoUpdateState = true
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        controller.toggle()
        
        #expect(mockPlayer.pauseCallCount == 1)
    }
    
    @Test("Stop completely stops playback")
    func stop() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        mockPlayer.shouldAutoUpdateState = true
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        controller.stop()
        
        #expect(mockPlayer.stopCallCount == 1)
        #expect(mockPlayer.isPlaying == false)
    }
    
    #endif
    
    @Test("isLoading covers Connecting state (playback intended but not yet playing)")
    func isLoadingCoversConnectingState() {
        let mockPlayer = MockAudioPlayer()
        // DISABLE auto updates to simulate latency/connecting
        mockPlayer.shouldAutoUpdateState = false
        
        #if os(iOS) || os(tvOS)
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        #else
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default,
            analytics: nil
        )
        #endif
        
        // Initial state
        #expect(controller.isLoading == false)
        
        // Start playing
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Player state is still .stopped (or whatever it was) because we disabled auto-update
        // BUT playbackIntended is true inside controller
        #expect(mockPlayer.state == .stopped)
        
        // This confirms the "Connecting" state logic:
        // isLoading should be true because we INTEND to play, even though player isn't playing/buffering yet
        #expect(controller.isLoading == true, "Should be loading in Connecting state (playback intending, player stopped)")
        
        // Transition to Buffering
        mockPlayer.simulateStateChange(to: .buffering)
        #expect(controller.isLoading == true, "Should be loading in Buffering state")
        
        // Transition to Playing
        mockPlayer.simulateStateChange(to: .playing)
        #expect(controller.isLoading == false, "Should NOT be loading in Playing state")
    }
    
    @Test("isLoading handles Error state correctly")
    func isLoadingHandlesErrorState() {
        let mockPlayer = MockAudioPlayer()
        
        // DISABLE auto updates
        mockPlayer.shouldAutoUpdateState = false
        
        #if os(iOS) || os(tvOS)
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        #else
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default,
            analytics: nil
        )
        #endif
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Initially connecting...
        #expect(controller.isLoading == true)
        
        // But then an error occurs
        mockPlayer.simulateStateChange(to: .error)
        
        // Should NOT show loading if error occurred, even if we implicitly intended to play
        // (Though usually error handling might reset intention, the property logic itself should be robust)
        #expect(controller.isLoading == false, "Should NOT load when in Error state")
    }
    
    @Test("Stop resets loading state")
    func stopResetsLoadingState() {
        let mockPlayer = MockAudioPlayer()
        mockPlayer.shouldAutoUpdateState = false
        
        #if os(iOS) || os(tvOS)
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        #else
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default,
            analytics: nil
        )
        #endif
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        #expect(controller.isLoading == true)
        
        controller.stop()
        
        #expect(controller.isLoading == false, "Stop should clear playback intention and loading state")
    }

}
