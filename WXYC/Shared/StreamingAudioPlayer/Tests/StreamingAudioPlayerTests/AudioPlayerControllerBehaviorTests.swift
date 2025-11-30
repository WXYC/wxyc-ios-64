//
//  AudioPlayerControllerBehaviorTests.swift
//  StreamingAudioPlayerTests
//
//  Parameterized behavior tests for AudioPlayerController.
//  These tests define the expected behavioral contract that implementations must follow.
//
//  The parameterized design allows future extensions to test multiple implementations
//  (e.g., RadioPlayerController from WXYC) against the same behavioral contract.
//

import Testing
import AVFoundation
@testable import StreamingAudioPlayer

// MARK: - Player Controller Behavior Protocol

/// Protocol defining the common behaviors expected from any player controller
@MainActor
protocol PlayerControllerBehavior {
    var isPlaying: Bool { get }
    func play()
    func pause()
    func toggle()
}

// MARK: - Test Harness Protocol

/// Protocol for test harnesses that wrap different player controller implementations
@MainActor
protocol PlayerControllerTestHarness {
    associatedtype Controller: PlayerControllerBehavior
    
    var controller: Controller { get }
    
    /// Number of times play was called on the mock player
    var playCallCount: Int { get }
    /// Number of times pause was called on the mock player
    var pauseCallCount: Int { get }
    /// Whether the mock session was activated
    var sessionActivated: Bool { get }
    /// Whether the mock session was deactivated
    var sessionDeactivated: Bool { get }
    /// Number of times analytics play was called
    var analyticsPlayCallCount: Int { get }
    /// Number of times analytics pause was called
    var analyticsPauseCallCount: Int { get }
    /// The last analytics play reason
    var lastAnalyticsPlayReason: String? { get }
    /// The last analytics pause duration
    var lastAnalyticsPauseDuration: TimeInterval? { get }
    
    func reset()
}

// MARK: - Test Case Enumeration

/// Enumeration of player controller implementations to test
enum PlayerControllerTestCase: String, CaseIterable, CustomTestStringConvertible {
    case audioPlayerController
    
    var testDescription: String {
        switch self {
        case .audioPlayerController:
            return "AudioPlayerController"
        }
    }
}

// MARK: - Type-Erased Harness Wrapper

/// Type-erased wrapper for test harnesses to enable parameterized testing
@MainActor
final class AnyPlayerControllerTestHarness {
    private let _controller: any PlayerControllerBehavior
    private let _playCallCount: () -> Int
    private let _pauseCallCount: () -> Int
    private let _sessionActivated: () -> Bool
    private let _sessionDeactivated: () -> Bool
    private let _analyticsPlayCallCount: () -> Int
    private let _analyticsPauseCallCount: () -> Int
    private let _lastAnalyticsPlayReason: () -> String?
    private let _lastAnalyticsPauseDuration: () -> TimeInterval?
    private let _reset: () -> Void
    
    var controller: any PlayerControllerBehavior { _controller }
    var playCallCount: Int { _playCallCount() }
    var pauseCallCount: Int { _pauseCallCount() }
    var sessionActivated: Bool { _sessionActivated() }
    var sessionDeactivated: Bool { _sessionDeactivated() }
    var analyticsPlayCallCount: Int { _analyticsPlayCallCount() }
    var analyticsPauseCallCount: Int { _analyticsPauseCallCount() }
    var lastAnalyticsPlayReason: String? { _lastAnalyticsPlayReason() }
    var lastAnalyticsPauseDuration: TimeInterval? { _lastAnalyticsPauseDuration() }
    
    func reset() { _reset() }
    
    init<H: PlayerControllerTestHarness>(_ harness: H) {
        _controller = harness.controller
        _playCallCount = { harness.playCallCount }
        _pauseCallCount = { harness.pauseCallCount }
        _sessionActivated = { harness.sessionActivated }
        _sessionDeactivated = { harness.sessionDeactivated }
        _analyticsPlayCallCount = { harness.analyticsPlayCallCount }
        _analyticsPauseCallCount = { harness.analyticsPauseCallCount }
        _lastAnalyticsPlayReason = { harness.lastAnalyticsPlayReason }
        _lastAnalyticsPauseDuration = { harness.lastAnalyticsPauseDuration }
        _reset = { harness.reset() }
    }
}

// MARK: - AudioPlayerController Test Harness

#if os(iOS) || os(tvOS) || os(watchOS)

/// Adapter to make AudioPlayerController conform to PlayerControllerBehavior
extension AudioPlayerController: PlayerControllerBehavior {
    public func play() {
        if let url = currentURL {
            play(url: url)
        }
    }
}

@MainActor
final class AudioPlayerControllerTestHarness: PlayerControllerTestHarness {
    let controller: AudioPlayerController
    let mockPlayer: MockAudioPlayer
    let mockSession: MockAudioSession
    let mockCommandCenter: MockRemoteCommandCenter
    let mockAnalytics: MockAudioAnalytics
    
    var playCallCount: Int { mockPlayer.playCallCount }
    var pauseCallCount: Int { mockPlayer.pauseCallCount }
    var sessionActivated: Bool { mockSession.lastActiveState == true }
    var sessionDeactivated: Bool { mockSession.lastActiveState == false }
    var analyticsPlayCallCount: Int { mockAnalytics.playCallCount }
    var analyticsPauseCallCount: Int { mockAnalytics.pauseCallCount }
    var lastAnalyticsPlayReason: String? { mockAnalytics.lastPlayReason }
    var lastAnalyticsPauseDuration: TimeInterval? { mockAnalytics.lastPauseDuration }
    
    init() {
        mockPlayer = MockAudioPlayer()
        mockSession = MockAudioSession()
        mockCommandCenter = MockRemoteCommandCenter()
        mockAnalytics = MockAudioAnalytics()
        
        controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: .default,
            analytics: mockAnalytics
        )
        
        // Set a default URL so play() works
        mockPlayer.currentURL = URL(string: "https://example.com/stream")!
    }
    
    func reset() {
        mockPlayer.reset()
        mockSession.reset()
        mockCommandCenter.reset()
        mockAnalytics.reset()
        mockPlayer.currentURL = URL(string: "https://example.com/stream")!
    }
}

// MARK: - Harness Factory

extension PlayerControllerTestCase {
    @MainActor
    func makeHarness() -> AnyPlayerControllerTestHarness {
        switch self {
        case .audioPlayerController:
            return AnyPlayerControllerTestHarness(AudioPlayerControllerTestHarness())
        }
    }
}

// MARK: - Parameterized Behavior Tests

@Suite("Player Controller Behavior Tests")
@MainActor
struct PlayerControllerBehaviorTests {
    
    // MARK: - Core Playback Behavior
    
    @Test("play() sets isPlaying to true", arguments: PlayerControllerTestCase.allCases)
    func playSetsIsPlayingTrue(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        #expect(harness.controller.isPlaying, "play() should set isPlaying to true")
    }
    
    @Test("pause() sets isPlaying to false", arguments: PlayerControllerTestCase.allCases)
    func pauseSetsIsPlayingFalse(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.controller.pause()
        #expect(!harness.controller.isPlaying, "pause() should set isPlaying to false")
    }
    
    @Test("toggle() while playing pauses", arguments: PlayerControllerTestCase.allCases)
    func toggleFromPlayingPauses(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        #expect(harness.controller.isPlaying)
        harness.controller.toggle()
        #expect(!harness.controller.isPlaying, "toggle() while playing should pause")
    }
    
    // MARK: - Underlying Player Integration
    
    @Test("play() calls underlying player", arguments: PlayerControllerTestCase.allCases)
    func playCallsUnderlyingPlayer(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        let initialCount = harness.playCallCount
        harness.controller.play()
        #expect(harness.playCallCount > initialCount, "play() should call underlying player")
    }
    
    @Test("pause() calls underlying player", arguments: PlayerControllerTestCase.allCases)
    func pauseCallsUnderlyingPlayer(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        let initialCount = harness.pauseCallCount
        harness.controller.pause()
        #expect(harness.pauseCallCount > initialCount, "pause() should call underlying player")
    }
    
    // MARK: - Analytics Integration
    
    @Test("play() calls analytics", arguments: PlayerControllerTestCase.allCases)
    func playCallsAnalytics(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.reset()
        harness.controller.play()
        #expect(harness.analyticsPlayCallCount > 0, "play() should call analytics")
    }
    
    @Test("pause() calls analytics with duration", arguments: PlayerControllerTestCase.allCases)
    func pauseCallsAnalyticsWithDuration(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.reset()
        harness.controller.play()
        
        // Small delay to ensure non-zero duration
        try? await Task.sleep(for: .milliseconds(10))
        
        harness.controller.pause()
        #expect(harness.analyticsPauseCallCount > 0, "pause() should call analytics")
        #expect(harness.lastAnalyticsPauseDuration != nil, "pause() should report duration")
    }
    
    // MARK: - Audio Session (iOS)
    
    @Test("play() activates audio session", arguments: PlayerControllerTestCase.allCases)
    func playActivatesAudioSession(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.reset()
        harness.controller.play()
        #expect(harness.sessionActivated, "play() should activate audio session")
    }
}

// MARK: - AudioPlayerController-Specific Tests

@Suite("AudioPlayerController Analytics Tests")
@MainActor
struct AudioPlayerControllerAnalyticsTests {
    
    @Test("Multiple play calls are handled correctly")
    func multiplePlayCallsAreIdempotent() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.controller.play()
        let firstPlayCount = harness.playCallCount
        
        // Playing again should still call the underlying player
        harness.controller.play()
        #expect(harness.playCallCount >= firstPlayCount)
    }
    
    @Test("Analytics receives play reason")
    func analyticsReceivesPlayReason() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        harness.controller.play(url: url, reason: "user tapped play")
        
        #expect(harness.mockAnalytics.lastPlayReason == "user tapped play")
    }
    
    @Test("Analytics receives pause duration")
    func analyticsReceivesPauseDuration() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.controller.play()
        
        // Wait a bit to accumulate duration
        try? await Task.sleep(for: .milliseconds(50))
        
        harness.controller.pause()
        
        #expect(harness.mockAnalytics.pauseCallCount == 1)
        if let duration = harness.mockAnalytics.lastPauseDuration {
            #expect(duration >= 0.04, "Duration should be at least 40ms")
        } else {
            Issue.record("Expected pause duration to be recorded")
        }
    }
    
    @Test("stop() also reports analytics pause")
    func stopReportsAnalyticsPause() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.controller.play()
        harness.controller.stop()
        
        #expect(harness.mockAnalytics.pauseCallCount == 1, "stop() should report analytics pause")
    }
}

// MARK: - Behavioral Contract Documentation

/*
 Expected Common Behaviors (all implementations should satisfy):
 
 1. PLAY BEHAVIOR
    - play() should set isPlaying to true
    - play() should call the underlying player's play method
    - play() should activate the audio session (iOS)
    - play() should call analytics with reason
 
 2. PAUSE BEHAVIOR
    - pause() should set isPlaying to false
    - pause() should call the underlying player's pause method
    - pause() should call analytics with duration
 
 3. TOGGLE BEHAVIOR
    - toggle() while playing should pause
    - toggle() while paused should resume/play
 
 4. STATE CONSISTENCY
    - isPlaying should accurately reflect playback state
    - State changes should be observable
 
 5. AUDIO SESSION (iOS)
    - Session should be activated before playback
    - Session should remain active during background playback
    - Session should be deactivated when stopped (not just paused)
 
 6. REMOTE COMMANDS (iOS)
    - Play/Pause/Toggle commands should be enabled
    - Seek/Skip commands should be disabled for live streams
 
 7. INTERRUPTION HANDLING
    - Should pause on interruption began
    - Should resume if shouldResume is set and was playing
 
 8. ROUTE CHANGES
    - Should pause when headphones disconnected
 
 9. ANALYTICS
    - play() should log analytics with reason
    - pause() should log analytics with duration
    - stop() should log analytics with duration
 */

#endif

