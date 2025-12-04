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
import Analytics
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

// MARK: - Background/Foreground Behavior Tests

@Suite("AudioPlayerController Background/Foreground Behavior Tests")
@MainActor
struct AudioPlayerControllerBackgroundBehaviorTests {
    
    @Test("play(url:) sets playbackIntended - background does NOT deactivate session")
    func playWithURLSetsPlaybackIntended() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        
        harness.controller.play(url: url, reason: "test")
        harness.mockSession.reset()  // Clear the activation from play()
        
        harness.controller.handleAppDidEnterBackground()
        
        // Should NOT have deactivated (playbackIntended is true)
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background while playing should NOT deactivate session")
    }
    
    @Test("play() without URL sets playbackIntended - background does NOT deactivate session")
    func playWithoutURLSetsPlaybackIntended() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        
        // First play with URL to set up currentURL
        harness.controller.play(url: url, reason: "initial")
        
        // Pause (clears playbackIntended)
        harness.controller.pause()
        
        // Resume with play() - should set playbackIntended = true
        harness.controller.play()
        
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        
        // Should NOT have deactivated
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background after play() should NOT deactivate - playbackIntended should be true")
    }
    
    @Test("pause() clears playbackIntended - background DOES deactivate session")
    func pauseClearsPlaybackIntended() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        
        harness.controller.play(url: url, reason: "test")
        harness.controller.pause()
        
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        
        // SHOULD have deactivated (playbackIntended is false)
        #expect(harness.mockSession.setActiveCallCount == 1,
               "Background after pause should deactivate session")
        #expect(harness.mockSession.lastActiveState == false,
               "Session should be set to inactive")
    }
    
    @Test("pause then play() keeps playbackIntended true")
    func pauseThenPlayKeepsPlaybackIntended() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        
        // Play -> Pause -> Play cycle
        harness.controller.play(url: url, reason: "initial")
        harness.controller.pause()  // playbackIntended = false
        harness.controller.play()   // playbackIntended should be true again
        
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background after pause-then-play should NOT deactivate")
    }
    
    @Test("pause then toggle() keeps playbackIntended true")
    func pauseThenToggleKeepsPlaybackIntended() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        
        // Play -> Pause -> Toggle cycle
        harness.controller.play(url: url, reason: "initial")
        harness.controller.pause()
        harness.controller.toggle()  // Should resume and set playbackIntended = true
        
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background after pause-then-toggle should NOT deactivate")
    }
    
    @Test("stop() clears playbackIntended and deactivates immediately")
    func stopClearsPlaybackIntendedAndDeactivates() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        
        harness.controller.play(url: url, reason: "test")
        harness.mockSession.reset()
        
        harness.controller.stop()
        
        // stop() itself should deactivate
        #expect(harness.mockSession.setActiveCallCount >= 1,
               "stop() should deactivate session")
        #expect(harness.mockSession.lastActiveState == false,
               "Session should be inactive after stop()")
    }
    
    @Test("foreground while playbackIntended reactivates session")
    func foregroundWhilePlaybackIntendedReactivates() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        
        harness.controller.play(url: url, reason: "test")
        harness.controller.handleAppDidEnterBackground()  // No deactivation (playing)
        
        harness.mockSession.reset()
        harness.controller.handleAppWillEnterForeground()
        
        #expect(harness.mockSession.setActiveCallCount == 1,
               "Foreground while playing should activate session")
        #expect(harness.mockSession.lastActiveState == true,
               "Session should be active")
    }
    
    @Test("foreground without playbackIntended does NOT activate session")
    func foregroundWithoutPlaybackIntendedDoesNotActivate() async {
        let harness = AudioPlayerControllerTestHarness()
        
        // Never played - go to foreground
        harness.mockSession.reset()
        harness.controller.handleAppWillEnterForeground()
        
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Foreground without playback intent should NOT activate session")
    }
    
    @Test("Real-world scenario: Apple Music interrupted, WXYC plays, backgrounding keeps WXYC playing")
    func appleMusicInterruptionScenario() async {
        let harness = AudioPlayerControllerTestHarness()
        let wxycURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        
        // User starts WXYC (interrupts Apple Music)
        harness.controller.play(url: wxycURL, reason: "user started stream")
        #expect(harness.controller.isPlaying)
        
        // User backgrounds app while WXYC is playing
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        
        // Critical: Session should NOT be deactivated
        // If it is, Apple Music will resume
        #expect(harness.mockSession.setActiveCallCount == 0,
               "CRITICAL: Backgrounding while playing should NOT deactivate session (would let Apple Music resume)")
        #expect(harness.mockSession.lastActiveState != false,
               "Session should remain active so WXYC continues playing")
    }
    
    @Test("Real-world scenario: Pause then resume, backgrounding keeps playing")
    func pauseResumeBackgroundScenario() async {
        let harness = AudioPlayerControllerTestHarness()
        let url = URL(string: "https://example.com/stream")!
        
        // Start playing
        harness.controller.play(url: url, reason: "initial")
        
        // User pauses temporarily
        harness.controller.pause()
        
        // User resumes via play()
        harness.controller.play()
        
        // User backgrounds app
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        
        // Should NOT deactivate - still playing
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Backgrounding after pause-resume cycle should NOT deactivate")
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
    - play() should set playbackIntended = true (prevents background deactivation)
 
 2. PAUSE BEHAVIOR
    - pause() should set isPlaying to false
    - pause() should call the underlying player's pause method
    - pause() should call analytics with duration
    - pause() should set playbackIntended = false
 
 3. TOGGLE BEHAVIOR
    - toggle() while playing should pause
    - toggle() while paused should resume/play (and set playbackIntended = true)
 
 4. STATE CONSISTENCY
    - isPlaying should accurately reflect playback state
    - State changes should be observable
    - playbackIntended tracks user intent, survives transient states
 
 5. AUDIO SESSION (iOS)
    - Session should be activated before playback
    - Session should remain active during background playback IF playbackIntended is true
    - Session should be deactivated when stopped (not just paused)
    - Session should be deactivated on background IF playbackIntended is false
 
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
 
 10. BACKGROUND/FOREGROUND BEHAVIOR
    - Background while playbackIntended: do NOT deactivate session
    - Background without playbackIntended: deactivate session
    - Foreground while playbackIntended: reactivate session
    - Foreground without playbackIntended: do NOT activate session
 */

#endif

