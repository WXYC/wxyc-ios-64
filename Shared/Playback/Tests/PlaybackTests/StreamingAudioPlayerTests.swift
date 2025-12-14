//
//  StreamingAudioPlayerTests.swift
//  StreamingAudioPlayer
//

import Testing
import AVFoundation
@testable import Playback

@Suite("StreamingAudioPlayer Tests")
struct StreamingAudioPlayerTests {
    
    @Test("Initial state is stopped")
    @MainActor
    func initialState() {
        let player = StreamingAudioPlayer()
        #expect(player.isPlaying == false)
        #expect(player.state == .stopped)
        #expect(player.currentURL == nil)
    }
    
    @Test("AudioPlayerPlaybackState has all expected cases")
    func playbackStateHasExpectedCases() {
        let states: [AudioPlayerPlaybackState] = [
            .stopped,
            .playing,
            .paused,
            .buffering,
            .error
        ]
        #expect(states.count == 5)
    }
    
    @Test("MockAudioPlayer conforms to AudioPlayerProtocol")
    @MainActor
    func mockPlayerConformsToProtocol() {
        let player: AudioPlayerProtocol = MockAudioPlayer()
        #expect(player.isPlaying == false)
        #expect(player.state == .stopped)
        #expect(player.currentURL == nil)
    }
}



// MARK: - Background/Foreground Behavior Tests (iOS)

#if os(iOS) || os(tvOS) || os(watchOS)

@Suite("AudioPlayerController Background/Foreground Tests")
@MainActor
struct AudioPlayerControllerBackgroundTests {
    
    @Test("Background while playing does NOT deactivate session")
    func backgroundWhilePlayingDoesNotDeactivate() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        // Reset the session's call count after init (which calls setCategory)
        mockSession.reset()
        
        // Start playing
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Reset again to only count background-related calls
        mockSession.reset()
        
        // Enter background while playing
        controller.handleAppDidEnterBackground()
        
        // Should NOT have deactivated the session
        #expect(mockSession.setActiveCallCount == 0, 
               "Background while playing should NOT deactivate audio session")
    }
    
    @Test("Background after pause DOES deactivate session")
    func backgroundAfterPauseDeactivates() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        // Start playing
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Pause
        controller.pause()
        
        // Reset to only count background-related calls
        mockSession.reset()
        
        // Enter background after pausing
        controller.handleAppDidEnterBackground()
        
        // Should have deactivated the session
        #expect(mockSession.setActiveCallCount == 1,
               "Background after pause should deactivate audio session")
        #expect(mockSession.lastActiveState == false,
               "Session should be set to inactive")
    }
    
    @Test("Background after stop DOES deactivate session")
    func backgroundAfterStopDeactivates() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        // Start playing
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Stop (this also deactivates, so we need to count total)
        mockSession.reset()
        controller.stop()
        
        // stop() already deactivates, so we should have at least one deactivation
        #expect(mockSession.setActiveCallCount >= 1,
               "Stop should deactivate audio session")
        
        // Additional background should also work but may not add more calls
        controller.handleAppDidEnterBackground()
        
        // Verify session was set to inactive at some point
        #expect(mockSession.lastActiveState == false,
               "Session should be inactive after stop and background")
    }
    
    @Test("Pause then play() keeps playbackIntended true - background does not deactivate")
    func pauseThenPlayKeepsPlaybackIntended() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        // Start playing with URL
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Pause (this sets playbackIntended = false)
        controller.pause()
        
        // Resume with play() - this should now set playbackIntended = true
        controller.play()
        
        // Reset to count only background calls
        mockSession.reset()
        
        // Enter background
        controller.handleAppDidEnterBackground()
        
        // Should NOT deactivate because we're playing again
        #expect(mockSession.setActiveCallCount == 0,
               "Background after pause-then-play should NOT deactivate - playbackIntended should be true")
    }
    
    @Test("Pause then toggle() keeps playbackIntended true - background does not deactivate")
    func pauseThenToggleKeepsPlaybackIntended() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        // Start playing with URL
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Pause
        controller.pause()
        
        // Toggle (should resume and set playbackIntended = true)
        controller.toggle()
        
        // Reset to count only background calls
        mockSession.reset()
        
        // Enter background
        controller.handleAppDidEnterBackground()
        
        // Should NOT deactivate
        #expect(mockSession.setActiveCallCount == 0,
               "Background after pause-then-toggle should NOT deactivate")
    }
    
    @Test("Foreground while playback intended reactivates session")
    func foregroundWhilePlaybackIntendedReactivates() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        // Start playing
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Simulate going to background while playing (no deactivation)
        controller.handleAppDidEnterBackground()
        
        // Reset to count only foreground calls
        mockSession.reset()
        
        // Return to foreground
        controller.handleAppWillEnterForeground()
        
        // Should activate session
        #expect(mockSession.setActiveCallCount == 1,
               "Foreground while playing should activate audio session")
        #expect(mockSession.lastActiveState == true,
               "Session should be set to active")
    }
    
    @Test("Foreground when not playing does NOT reactivate session")
    func foregroundWhenNotPlayingDoesNotActivate() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        // Never started playing - just enter foreground
        mockSession.reset()
        
        controller.handleAppWillEnterForeground()
        
        // Should NOT activate since we never intended to play
        #expect(mockSession.setActiveCallCount == 0,
               "Foreground without playback intent should NOT activate session")
    }
    
    @Test("isLoading reflects buffering state when playbackIntended is true")
    func isLoadingReflectsBufferingState() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: nil
        )
        
        // Initially not loading
        #expect(controller.isLoading == false)
        
        // Start playing - player goes to buffering first
        let url = URL(string: "https://example.com/stream")!
        mockPlayer.state = .buffering
        mockPlayer.currentURL = url
        controller.play(url: url)
        
        // Note: The mock sets state to .playing immediately in play(url:)
        // So we need to manually simulate buffering
        mockPlayer.simulateStateChange(to: .buffering)
        
        // Now isLoading should be true (playbackIntended is true, state is buffering)
        // However, isPlaying will also be true since buffering counts as "playing"
        // The controller checks: playbackIntended && player.state == .buffering
        #expect(controller.isLoading == true, "isLoading should be true when buffering with playback intended")
    }
}

#endif

