//
//  StreamingAudioPlayerTests.swift
//  StreamingAudioPlayer
//

import Testing
import AVFoundation
@testable import StreamingAudioPlayer

@Suite("StreamingAudioPlayer Tests")
struct StreamingAudioPlayerTests {
    
    @Test("Initial state is stopped")
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
    func mockPlayerConformsToProtocol() {
        let player: AudioPlayerProtocol = MockAudioPlayer()
        #expect(player.isPlaying == false)
        #expect(player.state == .stopped)
        #expect(player.currentURL == nil)
    }
}

@Suite("AudioPlayerController Tests")
@MainActor
struct AudioPlayerControllerTests {
    
    #if os(iOS) || os(tvOS) || os(watchOS)
    
    @Test("Play with URL starts playback")
    func playWithURL() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default
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
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default
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
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default
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
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default
        )
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        controller.stop()
        
        #expect(mockPlayer.stopCallCount == 1)
        #expect(mockPlayer.isPlaying == false)
    }
    
    @Test("Audio session configured on init")
    func audioSessionConfiguredOnInit() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        _ = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default
        )
        
        #expect(mockSession.setCategoryCallCount == 1)
        #expect(mockSession.lastCategory == .playback)
    }
    
    @Test("Remote commands configured correctly")
    func remoteCommandsConfigured() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        _ = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default
        )
        
        #expect(mockCommandCenter.playCommand.isEnabled == true)
        #expect(mockCommandCenter.pauseCommand.isEnabled == true)
        #expect(mockCommandCenter.togglePlayPauseCommand.isEnabled == true)
        #expect(mockCommandCenter.stopCommand.isEnabled == false)
    }
    
    @Test("isPlaying reflects player state")
    func isPlayingReflectsPlayerState() {
        let mockPlayer = MockAudioPlayer()
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default
        )
        
        #expect(controller.isPlaying == false)
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        #expect(controller.isPlaying == true)
        
        controller.pause()
        
        #expect(controller.isPlaying == false)
    }
    
    #else
    
    // macOS tests
    
    @Test("Play with URL starts playback (macOS)")
    func playWithURLMacOS() {
        let mockPlayer = MockAudioPlayer()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default
        )
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        #expect(mockPlayer.playCallCount == 1)
        #expect(mockPlayer.lastPlayedURL == url)
        #expect(mockPlayer.isPlaying == true)
    }
    
    @Test("Pause stops playback (macOS)")
    func pauseMacOS() {
        let mockPlayer = MockAudioPlayer()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default
        )
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        controller.pause()
        
        #expect(mockPlayer.pauseCallCount == 1)
        #expect(mockPlayer.isPlaying == false)
    }
    
    @Test("Stop completely stops playback (macOS)")
    func stopMacOS() {
        let mockPlayer = MockAudioPlayer()
        
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default
        )
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        controller.stop()
        
        #expect(mockPlayer.stopCallCount == 1)
        #expect(mockPlayer.isPlaying == false)
    }
    
    #endif
}

