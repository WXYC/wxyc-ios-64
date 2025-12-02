//
//  AudioPlayerControllerTests.swift
//  PlayerHeaderViewTests
//
//  Tests for AudioPlayerController with mock dependencies
//

import XCTest
import AVFoundation
#if os(iOS)
import UIKit
#endif
@testable import StreamingAudioPlayer

#if os(iOS) || os(tvOS) || os(watchOS)

@MainActor
final class AudioPlayerControllerTests: XCTestCase {
    
    var mockPlayer: MockAudioPlayer!
    var mockSession: MockAudioSession!
    var mockCommandCenter: MockRemoteCommandCenter!
    var controller: AudioPlayerController!
    
    override func setUp() async throws {
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
    
    override func tearDown() async throws {
        mockPlayer = nil
        mockSession = nil
        mockCommandCenter = nil
        controller = nil
    }
    
    // MARK: - Playback Tests
    
    func testPlayWithURL() {
        let url = URL(string: "https://example.com/stream")!
        
        controller.play(url: url)
        
        XCTAssertEqual(mockPlayer.playCallCount, 1)
        XCTAssertEqual(mockPlayer.lastPlayedURL, url)
        XCTAssertTrue(mockPlayer.isPlaying)
    }
    
    func testPause() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.pause()
        
        XCTAssertEqual(mockPlayer.pauseCallCount, 1)
        XCTAssertFalse(mockPlayer.isPlaying)
    }
    
    func testToggleFromStopped() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        mockPlayer.pause() // Simulate paused state
        
        controller.toggle()
        
        XCTAssertEqual(mockPlayer.resumeCallCount, 1)
    }
    
    func testToggleFromPlaying() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.toggle()
        
        XCTAssertEqual(mockPlayer.pauseCallCount, 1)
    }
    
    func testStop() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.stop()
        
        XCTAssertEqual(mockPlayer.stopCallCount, 1)
        XCTAssertFalse(mockPlayer.isPlaying)
    }
    
    // MARK: - Audio Session Tests
    
    func testAudioSessionConfiguredOnInit() {
        // Session category should be set during init
        XCTAssertEqual(mockSession.setCategoryCallCount, 1)
        XCTAssertEqual(mockSession.lastCategory, .playback)
    }
    
    func testAudioSessionActivatedOnPlay() {
        let url = URL(string: "https://example.com/stream")!
        
        controller.play(url: url)
        
        XCTAssertEqual(mockSession.setActiveCallCount, 1)
        XCTAssertEqual(mockSession.lastActiveState, true)
    }
    
    func testAudioSessionDeactivatedOnStop() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.stop()
        
        XCTAssertEqual(mockSession.setActiveCallCount, 2) // Once for play, once for stop
        XCTAssertEqual(mockSession.lastActiveState, false)
    }
    
    // MARK: - Remote Command Center Tests
    
    func testRemoteCommandsConfigured() {
        XCTAssertTrue(mockCommandCenter.playCommand.isEnabled)
        XCTAssertTrue(mockCommandCenter.pauseCommand.isEnabled)
        XCTAssertTrue(mockCommandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertFalse(mockCommandCenter.stopCommand.isEnabled)
        XCTAssertFalse(mockCommandCenter.skipForwardCommand.isEnabled)
        XCTAssertFalse(mockCommandCenter.skipBackwardCommand.isEnabled)
    }
    
    func testRemoteCommandTargetsAdded() {
        XCTAssertFalse(mockCommandCenter.mockPlayCommand.targets.isEmpty)
        XCTAssertFalse(mockCommandCenter.mockPauseCommand.targets.isEmpty)
        XCTAssertFalse(mockCommandCenter.mockTogglePlayPauseCommand.targets.isEmpty)
    }
    
    // MARK: - IsPlaying State Tests
    
    func testIsPlayingReflectsPlayerState() {
        XCTAssertFalse(controller.isPlaying)
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        XCTAssertTrue(controller.isPlaying)
        
        controller.pause()
        
        XCTAssertFalse(controller.isPlaying)
    }
    
    // MARK: - Callback Tests
    
    func testSetAudioBufferHandler() {
        var receivedBuffer: AVAudioPCMBuffer?
        
        controller.setAudioBufferHandler { buffer in
            receivedBuffer = buffer
        }
        
        // Create a mock buffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        
        mockPlayer.simulateAudioBuffer(buffer)
        
        XCTAssertNotNil(receivedBuffer)
    }
    
    func testSetMetadataHandler() {
        var receivedMetadata: [String: String]?
        
        controller.setMetadataHandler { metadata in
            receivedMetadata = metadata
        }
        
        let testMetadata = ["StreamTitle": "Test Song"]
        mockPlayer.simulateMetadata(testMetadata)
        
        XCTAssertEqual(receivedMetadata?["StreamTitle"], "Test Song")
    }
    
    // MARK: - App Lifecycle Tests (iOS only)
    // These tests verify the public lifecycle methods that should be called
    // from SwiftUI's scenePhase handler
    
    #if os(iOS)
    func testBackgroundWhileNotPlayingDeactivatesSession() {
        // Not playing, go to background
        mockSession.reset()
        
        controller.handleAppDidEnterBackground()
        
        // Session should be deactivated when not playing
        XCTAssertEqual(mockSession.lastActiveState, false)
    }
    
    func testBackgroundWhilePlayingKeepsSessionActive() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        mockSession.reset() // Reset to track only background behavior
        
        controller.handleAppDidEnterBackground()
        
        // Session should NOT be deactivated when playing (no setActive call)
        XCTAssertEqual(mockSession.setActiveCallCount, 0)
    }
    
    func testForegroundWhilePlayingActivatesSession() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        mockSession.reset() // Reset to track only foreground behavior
        
        controller.handleAppWillEnterForeground()
        
        // Session should be activated when returning to foreground while playing
        XCTAssertEqual(mockSession.lastActiveState, true)
    }
    
    func testForegroundWhileNotPlayingDoesNotActivateSession() {
        // Not playing, return to foreground
        mockSession.reset()
        
        controller.handleAppWillEnterForeground()
        
        // Session should NOT be activated when not playing
        XCTAssertEqual(mockSession.setActiveCallCount, 0)
    }
    
    func testRapidBackgroundForegroundTransitions() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        // Rapidly cycle between background and foreground
        for _ in 0..<10 {
            controller.handleAppDidEnterBackground()
            controller.handleAppWillEnterForeground()
        }
        
        // Should still be playing and session should be active
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(mockSession.lastActiveState, true)
    }
    
    func testBackgroundAfterPauseDeactivatesSession() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        controller.pause()
        mockSession.reset()
        
        controller.handleAppDidEnterBackground()
        
        // Session should be deactivated after pause + background
        XCTAssertEqual(mockSession.lastActiveState, false)
    }
    #endif
}

#else

// macOS tests - simplified without audio session/remote commands
@MainActor
final class AudioPlayerControllerTests: XCTestCase {
    
    var mockPlayer: MockAudioPlayer!
    var controller: AudioPlayerController!
    
    override func setUp() async throws {
        mockPlayer = MockAudioPlayer()
        controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: .default
        )
    }
    
    override func tearDown() async throws {
        mockPlayer = nil
        controller = nil
    }
    
    // MARK: - Playback Tests
    
    func testPlayWithURL() {
        let url = URL(string: "https://example.com/stream")!
        
        controller.play(url: url)
        
        XCTAssertEqual(mockPlayer.playCallCount, 1)
        XCTAssertEqual(mockPlayer.lastPlayedURL, url)
        XCTAssertTrue(mockPlayer.isPlaying)
    }
    
    func testPause() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.pause()
        
        XCTAssertEqual(mockPlayer.pauseCallCount, 1)
        XCTAssertFalse(mockPlayer.isPlaying)
    }
    
    func testToggleFromPlaying() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.toggle()
        
        XCTAssertEqual(mockPlayer.pauseCallCount, 1)
    }
    
    func testStop() {
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        controller.stop()
        
        XCTAssertEqual(mockPlayer.stopCallCount, 1)
        XCTAssertFalse(mockPlayer.isPlaying)
    }
    
    func testIsPlayingReflectsPlayerState() {
        XCTAssertFalse(controller.isPlaying)
        
        let url = URL(string: "https://example.com/stream")!
        controller.play(url: url)
        
        XCTAssertTrue(controller.isPlaying)
        
        controller.pause()
        
        XCTAssertFalse(controller.isPlaying)
    }
}

#endif
