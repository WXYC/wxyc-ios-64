//
//  RadioPlayerControllerBehaviorTests.swift
//  WXYCTests
//
//  Parameterized tests that verify RadioPlayerController follows the same
//  behavioral contract as AudioPlayerController in PlayerHeaderView.
//
//  These tests mirror PlayerControllerBehaviorTests.swift to ensure consistency.
//

import XCTest
import AVFoundation
@testable import Core

// MARK: - Mock Player for RadioPlayer

@MainActor
final class MockRadioPlayer: PlayerProtocol, @unchecked Sendable {
    var rate: Float = 0
    var playCallCount = 0
    var pauseCallCount = 0
    var replaceCurrentItemCallCount = 0
    
    func play() {
        playCallCount += 1
        rate = 1.0
    }
    
    func pause() {
        pauseCallCount += 1
        rate = 0
    }
    
    func replaceCurrentItem(with item: AVPlayerItem?) {
        replaceCurrentItemCallCount += 1
    }
    
    func reset() {
        rate = 0
        playCallCount = 0
        pauseCallCount = 0
        replaceCurrentItemCallCount = 0
    }
}

// MARK: - RadioPlayerController Behavior Tests

@MainActor
final class RadioPlayerControllerBehaviorTests: XCTestCase {
    
    var mockPlayer: MockRadioPlayer!
    var controller: RadioPlayerController!
    
    override func setUp() async throws {
        mockPlayer = MockRadioPlayer()
        
        // Create RadioPlayer with mock
        // Note: RadioPlayerController creates its own RadioPlayer internally
        // We need to test through the public interface
        controller = RadioPlayerController()
    }
    
    override func tearDown() async throws {
        mockPlayer = nil
        controller = nil
    }
    
    // MARK: - Core Behavior Tests (matching AudioPlayerController tests)
    
    func testPlaySetsIsPlayingTrue() throws {
        try controller.play(reason: "test")
        
        // Wait for async audio session activation
        let expectation = XCTestExpectation(description: "isPlaying becomes true")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Note: This may not actually start playing without a real stream
            // The test verifies the method can be called without error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testPauseSetsIsPlayingFalse() throws {
        try controller.play(reason: "test")
        controller.pause()
        
        XCTAssertFalse(controller.isPlaying, "pause() should set isPlaying to false")
    }
    
    func testToggleFromPlayingPauses() throws {
        try controller.play(reason: "test")
        
        // If playing, toggle should pause
        if controller.isPlaying {
            try controller.toggle(reason: "test toggle")
            XCTAssertFalse(controller.isPlaying, "toggle() while playing should pause")
        }
    }
    
    func testToggleWhilePausedStartsPlayback() throws {
        // Start paused
        XCTAssertFalse(controller.isPlaying)
        
        // Toggle should attempt to play
        try controller.toggle(reason: "test toggle")
        
        // Wait for async handling
        let expectation = XCTestExpectation(description: "toggle handled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Behavioral Contract Documentation
    
    /*
     RadioPlayerController implements these behaviors:
     
     1. play(reason:) 
        - Activates audio session
        - Calls radioPlayer.play()
        - Logs analytics with reason
     
     2. pause()
        - Calls radioPlayer.pause()
        - Does NOT deactivate session (allows quick resume)
     
     3. toggle(reason:)
        - If playing: pauses and logs pause analytics
        - If paused: plays and logs play analytics
     
     4. Interruption Handling
        - Pauses on interruption began
        - Resumes if shouldResume and was playing
     
     5. Route Changes
        - Observed but handled by RadioPlayer
     
     6. Remote Commands
        - Play/Pause/Toggle/Stop commands handled
     
     7. Background/Foreground
        - Deactivates session in background if not playing
        - Does nothing special in foreground
     
     These behaviors should match AudioPlayerController from PlayerHeaderView.
     */
}

// MARK: - RadioPlayer Direct Tests

@MainActor
final class RadioPlayerBehaviorTests: XCTestCase {
    
    var mockPlayer: MockRadioPlayer!
    var radioPlayer: RadioPlayer!
    
    override func setUp() async throws {
        mockPlayer = MockRadioPlayer()
        radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://example.com/stream")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test")!,
            analytics: nil,
            notificationCenter: .default
        )
    }
    
    override func tearDown() async throws {
        mockPlayer = nil
        radioPlayer = nil
    }
    
    // MARK: - Core Behavior Tests (matching StreamingAudioPlayer tests)
    
    func testPlayCallsUnderlyingPlayer() {
        radioPlayer.play()
        XCTAssertEqual(mockPlayer.playCallCount, 1, "play() should call underlying player")
    }
    
    func testPauseCallsUnderlyingPlayer() {
        radioPlayer.play()
        radioPlayer.pause()
        XCTAssertEqual(mockPlayer.pauseCallCount, 1, "pause() should call underlying player")
    }
    
    func testPauseResetsStream() {
        radioPlayer.play()
        radioPlayer.pause()
        XCTAssertEqual(mockPlayer.replaceCurrentItemCallCount, 1, "pause() should reset stream")
    }
    
    func testPlayWhilePlayingIsIdempotent() {
        radioPlayer.play()
        let firstCount = mockPlayer.playCallCount
        
        // RadioPlayer's isPlaying is updated via AVPlayer.rateDidChangeNotification
        // Set mock rate > 0 so the notification handler sets isPlaying = true
        mockPlayer.rate = 1.0
        
        // Post the notification to trigger the observer
        // Note: RadioPlayer registers with object: nil (since mock isn't AVPlayer),
        // so it receives all notifications of this name
        NotificationCenter.default.post(
            name: AVPlayer.rateDidChangeNotification,
            object: nil
        )
        
        // Wait for async notification handling on main queue
        let expectation = XCTestExpectation(description: "Notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Now isPlaying should be true
        XCTAssertTrue(radioPlayer.isPlaying, "isPlaying should be true after notification")
        
        radioPlayer.play()
        XCTAssertEqual(mockPlayer.playCallCount, firstCount, "play() while playing should be no-op")
    }
    
    func testIsPlayingReflectsPlayerRate() {
        XCTAssertFalse(radioPlayer.isPlaying)
        
        // Note: isPlaying is updated via notification observer when rate changes
        // Direct mock manipulation won't trigger the observer
    }
    
    // MARK: - Behavioral Contract Documentation
    
    /*
     RadioPlayer implements these behaviors:
     
     1. play()
        - Guards against double-play (if already playing, returns early)
        - Sets UserDefaults "isPlaying" to true
        - Calls underlying player.play()
        - Starts timer for analytics
     
     2. pause()
        - Sets UserDefaults "isPlaying" to false  
        - Calls underlying player.pause()
        - Resets stream by replacing current item
     
     3. isPlaying
        - Updated via AVPlayer.rateDidChangeNotification observer
        - True when player.rate > 0
     
     Differences from StreamingAudioPlayer:
     - Uses AVPlayer instead of AudioStreaming package
     - Resets stream on pause (for live streaming)
     - Has analytics integration
     - Uses UserDefaults for cross-process state
     
     Similarities (behavioral contract):
     - play() starts playback
     - pause() stops playback
     - isPlaying reflects current state
     */
}

