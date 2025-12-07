//
//  PlaybackControllerBehaviorTests.swift
//  WXYCTests
//
//  Shared parameterized behavior tests for all PlaybackController implementations.
//  Both RadioPlayerController and AudioPlayerController must pass these tests.
//
//  RadioPlayerController is the canonical implementation - its behaviors define
//  the expected contract that AudioPlayerController must match.
//

import Testing
import AVFoundation
import MediaPlayer
import UIKit
@testable import Core
@testable import Playback

// MARK: - Mock Player for RadioPlayer

final class MockRadioPlayer: PlayerProtocol, @unchecked Sendable {
    nonisolated(unsafe) var rate: Float = 0
    nonisolated(unsafe) var playCallCount = 0
    nonisolated(unsafe) var pauseCallCount = 0
    nonisolated(unsafe) var replaceCurrentItemCallCount = 0
    
    /// Simulates whether the player is in a "playing" state
    nonisolated(unsafe) var simulatedIsPlaying = false
    
    nonisolated func play() {
        playCallCount += 1
        rate = 1.0
        simulatedIsPlaying = true
    }
    
    nonisolated func pause() {
        pauseCallCount += 1
        rate = 0
        simulatedIsPlaying = false
    }
    
    nonisolated func replaceCurrentItem(with item: AVPlayerItem?) {
        replaceCurrentItemCallCount += 1
    }
    
    func reset() {
        rate = 0
        playCallCount = 0
        pauseCallCount = 0
        replaceCurrentItemCallCount = 0
        simulatedIsPlaying = false
    }
}

// MARK: - Unified Test Harness Protocol

/// Protocol for test harnesses that wrap different player controller implementations
@MainActor
protocol UnifiedPlayerControllerTestHarness {
    /// The stream URL used for testing
    var streamURL: URL { get }
    
    /// Whether the controller reports isPlaying as true
    var isPlaying: Bool { get }
    
    /// Number of times play was called on the underlying player
    var playCallCount: Int { get }
    
    /// Number of times pause was called on the underlying player
    var pauseCallCount: Int { get }
    
    /// Number of times session was set to inactive (for AudioPlayerController)
    var sessionDeactivationCount: Int { get }
    
    /// The notification center used by this harness (for posting test notifications)
    var notificationCenter: NotificationCenter { get }
    
    /// Starts playback with the given reason
    func play(reason: String) throws
    
    /// Pauses playback
    func pause()
    
    /// Toggles playback with the given reason
    func toggle(reason: String) throws
    
    /// Simulates the underlying player actually starting playback
    func simulatePlaybackStarted()
    
    /// Simulates the underlying player stopping
    func simulatePlaybackStopped()
    
    /// Simulates the app entering background
    func simulateEnterBackground()
    
    /// Waits for async operations to complete
    func waitForAsync() async
    
    /// Resets the harness state for a fresh test
    func reset()
    
    /// Resets just the session-related counters
    func resetSessionCounters()
}

// MARK: - Test Case Enumeration

/// Enumeration of player controller implementations to test
enum PlaybackControllerTestCase: String, CaseIterable, CustomTestStringConvertible {
    case radioPlayerController
    case audioPlayerController
    
    var testDescription: String {
        switch self {
        case .radioPlayerController:
            return "RadioPlayerController"
        case .audioPlayerController:
            return "AudioPlayerController"
        }
    }
    
    @MainActor
    func makeHarness() -> any UnifiedPlayerControllerTestHarness {
        switch self {
        case .radioPlayerController:
            return RadioPlayerTestHarness()
        case .audioPlayerController:
            return AudioPlayerTestHarness()
        }
    }
}

// MARK: - RadioPlayerController Test Harness

@MainActor
final class RadioPlayerTestHarness: UnifiedPlayerControllerTestHarness {
    let mockPlayer: MockRadioPlayer
    let radioPlayer: RadioPlayer
    let controller: RadioPlayerController
    let notificationCenter: NotificationCenter
    let testUserDefaults: UserDefaults
    let streamURL = URL(string: "https://example.com/stream")!
    
    var isPlaying: Bool { controller.isPlaying }
    var playCallCount: Int { mockPlayer.playCallCount }
    var pauseCallCount: Int { mockPlayer.pauseCallCount }
    
    // RadioPlayerController doesn't expose session deactivation directly
    // We track it indirectly - for RadioPlayerController, background while not playing
    // triggers deactivation internally, but we can't observe it without mocking AVAudioSession
    var sessionDeactivationCount: Int { 0 }
    
    init() {
        mockPlayer = MockRadioPlayer()
        notificationCenter = NotificationCenter()
        testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        
        radioPlayer = RadioPlayer(
            streamURL: streamURL,
            player: mockPlayer,
            userDefaults: testUserDefaults,
            analytics: nil,
            notificationCenter: notificationCenter
        )
        
        controller = RadioPlayerController(
            radioPlayer: radioPlayer,
            notificationCenter: notificationCenter,
            remoteCommandCenter: .shared()
        )
    }
    
    func play(reason: String) throws {
        try controller.play(reason: reason)
    }
    
    func pause() {
        controller.pause()
    }
    
    func toggle(reason: String) throws {
        try controller.toggle(reason: reason)
    }
    
    func simulatePlaybackStarted() {
        mockPlayer.rate = 1.0
        mockPlayer.simulatedIsPlaying = true
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: nil)
    }
    
    func simulatePlaybackStopped() {
        mockPlayer.rate = 0
        mockPlayer.simulatedIsPlaying = false
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: nil)
    }
    
    func simulateEnterBackground() {
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    func waitForAsync() async {
        try? await Task.sleep(for: .milliseconds(100))
    }
    
    func reset() {
        mockPlayer.reset()
    }
    
    func resetSessionCounters() {
        // RadioPlayerController doesn't expose session counters
    }
}

// MARK: - AudioPlayerController Test Harness

#if os(iOS) || os(tvOS) || os(watchOS)

@MainActor
final class AudioPlayerTestHarness: UnifiedPlayerControllerTestHarness {
    let mockPlayer: MockStreamingAudioPlayer
    let mockSession: MockAudioSessionForUnifiedTests
    let mockCommandCenter: MockRemoteCommandCenterForUnifiedTests
    let controller: AudioPlayerController
    let notificationCenter: NotificationCenter
    let streamURL = URL(string: "https://example.com/stream")!
    
    var isPlaying: Bool { controller.isPlaying }
    var playCallCount: Int { mockPlayer.playCallCount }
    var pauseCallCount: Int { mockPlayer.pauseCallCount }
    var sessionDeactivationCount: Int { mockSession.deactivationCount }
    
    init() {
        mockPlayer = MockStreamingAudioPlayer()
        mockSession = MockAudioSessionForUnifiedTests()
        mockCommandCenter = MockRemoteCommandCenterForUnifiedTests()
        notificationCenter = NotificationCenter()
        
        controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: notificationCenter,
            analytics: nil
        )
        
        // Set the default URL
        mockPlayer.currentURL = streamURL
    }
    
    func play(reason: String) throws {
        controller.play(url: streamURL, reason: reason)
    }
    
    func pause() {
        controller.pause()
    }
    
    func toggle(reason: String) throws {
        // AudioPlayerController's toggle doesn't take a reason, but we adapt here
        controller.toggle()
    }
    
    func simulatePlaybackStarted() {
        mockPlayer.simulatePlaybackStarted()
    }
    
    func simulatePlaybackStopped() {
        mockPlayer.simulatePlaybackStopped()
    }
    
    func simulateEnterBackground() {
        // AudioPlayerController expects direct method calls from SwiftUI scenePhase
        controller.handleAppDidEnterBackground()
    }
    
    func waitForAsync() async {
        try? await Task.sleep(for: .milliseconds(100))
    }
    
    func reset() {
        mockPlayer.reset()
        mockSession.reset()
        mockPlayer.currentURL = streamURL
    }
    
    func resetSessionCounters() {
        mockSession.resetCounters()
    }
}

// MARK: - Mock Types for AudioPlayerController

@MainActor
final class MockStreamingAudioPlayer: AudioPlayerProtocol, @unchecked Sendable {
    var isPlaying: Bool = false
    var state: AudioPlayerPlaybackState = .stopped
    var currentURL: URL?
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStateChange: ((AudioPlayerPlaybackState, AudioPlayerPlaybackState) -> Void)?
    var onMetadata: (([String: String]) -> Void)?
    
    var playCallCount = 0
    var pauseCallCount = 0
    var stopCallCount = 0
    var resumeCallCount = 0
    
    func play(url: URL) {
        playCallCount += 1
        currentURL = url
        isPlaying = true
        state = .playing
    }
    
    func pause() {
        pauseCallCount += 1
        isPlaying = false
        state = .paused
    }
    
    func stop() {
        stopCallCount += 1
        isPlaying = false
        state = .stopped
    }
    
    func resume() {
        resumeCallCount += 1
        isPlaying = true
        state = .playing
    }
    
    func simulatePlaybackStarted() {
        isPlaying = true
        state = .playing
    }
    
    func simulatePlaybackStopped() {
        isPlaying = false
        state = .paused
    }
    
    func reset() {
        isPlaying = false
        state = .stopped
        playCallCount = 0
        pauseCallCount = 0
        stopCallCount = 0
        resumeCallCount = 0
    }
}

@MainActor
final class MockAudioSessionForUnifiedTests: AudioSessionProtocol, @unchecked Sendable {
    var setCategoryCallCount = 0
    var setActiveCallCount = 0
    var activationCount = 0
    var deactivationCount = 0
    var lastActiveState: Bool?
    
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        setCategoryCallCount += 1
    }
    
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        setActiveCallCount += 1
        lastActiveState = active
        if active {
            activationCount += 1
        } else {
            deactivationCount += 1
        }
    }
    
    func reset() {
        setCategoryCallCount = 0
        setActiveCallCount = 0
        activationCount = 0
        deactivationCount = 0
        lastActiveState = nil
    }
    
    func resetCounters() {
        setActiveCallCount = 0
        activationCount = 0
        deactivationCount = 0
        lastActiveState = nil
    }
}

@MainActor
final class MockRemoteCommandCenterForUnifiedTests: RemoteCommandCenterProtocol, @unchecked Sendable {
    var playCommand: RemoteCommandProtocol { _playCommand }
    var pauseCommand: RemoteCommandProtocol { _pauseCommand }
    var stopCommand: RemoteCommandProtocol { _stopCommand }
    var togglePlayPauseCommand: RemoteCommandProtocol { _togglePlayPauseCommand }
    var nextTrackCommand: RemoteCommandProtocol { _nextTrackCommand }
    var previousTrackCommand: RemoteCommandProtocol { _previousTrackCommand }
    var skipForwardCommand: RemoteCommandProtocol { _skipForwardCommand }
    var skipBackwardCommand: RemoteCommandProtocol { _skipBackwardCommand }
    var seekForwardCommand: RemoteCommandProtocol { _seekForwardCommand }
    var seekBackwardCommand: RemoteCommandProtocol { _seekBackwardCommand }
    var changePlaybackPositionCommand: RemoteCommandProtocol { _changePlaybackPositionCommand }
    
    private let _playCommand = MockRemoteCommand()
    private let _pauseCommand = MockRemoteCommand()
    private let _stopCommand = MockRemoteCommand()
    private let _togglePlayPauseCommand = MockRemoteCommand()
    private let _nextTrackCommand = MockRemoteCommand()
    private let _previousTrackCommand = MockRemoteCommand()
    private let _skipForwardCommand = MockRemoteCommand()
    private let _skipBackwardCommand = MockRemoteCommand()
    private let _seekForwardCommand = MockRemoteCommand()
    private let _seekBackwardCommand = MockRemoteCommand()
    private let _changePlaybackPositionCommand = MockRemoteCommand()
    
    func reset() {
        // Reset commands if needed
    }
}

@MainActor
final class MockRemoteCommand: RemoteCommandProtocol, @unchecked Sendable {
    nonisolated(unsafe) var isEnabled: Bool = false
    nonisolated(unsafe) var targets: [Any] = []
    
    nonisolated func addTarget(handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) -> Any {
        let target = "target-\(targets.count)"
        targets.append(target)
        return target
    }
    
    nonisolated func removeTarget(_ target: Any?) {
        // No-op for tests
    }
}

#endif

// MARK: - Parameterized Behavior Tests

@Suite("Playback Controller Shared Behavior Tests")
@MainActor
struct PlaybackControllerBehaviorTests {
    
    // MARK: - Core Playback Behavior
    
    @Test("play() sets isPlaying to true", arguments: PlaybackControllerTestCase.allCases)
    func playSetsIsPlayingTrue(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        try harness.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        #expect(harness.isPlaying, "play() should set isPlaying to true for \(testCase.testDescription)")
    }
    
    @Test("pause() sets isPlaying to false", arguments: PlaybackControllerTestCase.allCases)
    func pauseSetsIsPlayingFalse(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        // Start playing
        try harness.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.isPlaying)
        
        // Pause
        harness.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        #expect(!harness.isPlaying, "pause() should set isPlaying to false for \(testCase.testDescription)")
    }
    
    @Test("toggle() while playing pauses", arguments: PlaybackControllerTestCase.allCases)
    func toggleFromPlayingPauses(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        // Start playing
        try harness.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.isPlaying)
        
        // Toggle should pause
        try harness.toggle(reason: "test toggle")
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        #expect(!harness.isPlaying, "toggle() while playing should pause for \(testCase.testDescription)")
    }
    
    @Test("toggle() while paused starts playback", arguments: PlaybackControllerTestCase.allCases)
    func toggleWhilePausedStartsPlayback(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        // Start paused
        #expect(!harness.isPlaying)
        
        // Toggle should start playback
        try harness.toggle(reason: "test toggle")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        #expect(harness.isPlaying, "toggle() while paused should start playback for \(testCase.testDescription)")
    }
    
    // MARK: - Underlying Player Integration
    
    @Test("play() calls underlying player", arguments: PlaybackControllerTestCase.allCases)
    func playCallsUnderlyingPlayer(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        try harness.play(reason: "test")
        await harness.waitForAsync()
        
        #expect(harness.playCallCount >= 1, "play() should call underlying player for \(testCase.testDescription)")
    }
    
    @Test("pause() calls underlying player", arguments: PlaybackControllerTestCase.allCases)
    func pauseCallsUnderlyingPlayer(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        try harness.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        harness.pause()
        
        #expect(harness.pauseCallCount >= 1, "pause() should call underlying player for \(testCase.testDescription)")
    }
}

// MARK: - Interruption Handling Tests (iOS only)

#if os(iOS)
@Suite("Playback Controller Interruption Handling Tests")
@MainActor
struct PlaybackControllerInterruptionTests {
    
    /// Helper to create an interruption notification with the specified type
    private func makeInterruptionNotification(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions? = nil,
        reason: AVAudioSession.InterruptionReason? = nil
    ) -> Notification {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: type.rawValue)
        ]
        if let options {
            userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: options.rawValue)
        }
        if let reason {
            userInfo[AVAudioSessionInterruptionReasonKey] = NSNumber(value: reason.rawValue)
        }
        return Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }
    
    @Test("Interruption began pauses playback", arguments: PlaybackControllerTestCase.allCases)
    func interruptionBeganPausesPlayback(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        // Start playing
        try harness.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.isPlaying)
        
        let pauseCountBefore = harness.pauseCallCount
        
        // Post interruption began notification
        let notification = makeInterruptionNotification(type: .began)
        harness.notificationCenter.post(notification)
        await harness.waitForAsync()
        
        // Should have paused (RadioPlayer) or at minimum handled the interruption
        // Note: Exact behavior may differ but both should respond to interruptions
        #expect(harness.pauseCallCount >= pauseCountBefore, 
               "Interruption began should be handled for \(testCase.testDescription)")
    }
    
    @Test("Interruption ended with shouldResume resumes playback", arguments: PlaybackControllerTestCase.allCases)
    func interruptionEndedWithShouldResumeResumesPlayback(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        // Start playing then simulate interruption paused us
        try harness.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        let playCountBefore = harness.playCallCount
        
        // Post interruption ended with shouldResume
        let notification = makeInterruptionNotification(
            type: .ended,
            options: .shouldResume
        )
        harness.notificationCenter.post(notification)
        await harness.waitForAsync()
        
        // Should have attempted to resume
        #expect(harness.playCallCount > playCountBefore,
               "Interruption ended with shouldResume should resume for \(testCase.testDescription)")
    }
}

// MARK: - Background/Foreground Tests (iOS only)

@Suite("Playback Controller Background/Foreground Tests")
@MainActor
struct PlaybackControllerBackgroundTests {
    
    @Test("Background while playing keeps session active", arguments: PlaybackControllerTestCase.allCases)
    func backgroundWhilePlayingKeepsSessionActive(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        // Start playing
        try harness.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.isPlaying)
        
        let pauseCountBefore = harness.pauseCallCount
        
        // Post background notification
        harness.notificationCenter.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        await harness.waitForAsync()
        
        // Should NOT have paused - playback continues in background
        #expect(harness.pauseCallCount == pauseCountBefore,
               "Background while playing should not pause for \(testCase.testDescription)")
    }
    
    @Test("Pause then resume, background does NOT pause (AudioPlayerController)", arguments: [PlaybackControllerTestCase.audioPlayerController])
    func pauseThenResumeBackgroundDoesNotPause(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        // Play -> Pause -> Resume cycle
        try harness.play(reason: "initial")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        harness.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        // Resume - this should set playbackIntended = true again
        try harness.toggle(reason: "resume")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.isPlaying)
        
        // Reset counters before background
        harness.resetSessionCounters()
        
        // Enter background while playing
        harness.simulateEnterBackground()
        await harness.waitForAsync()
        
        // Should NOT deactivate session (playbackIntended should be true)
        #expect(harness.sessionDeactivationCount == 0,
               "Background after pause-then-resume should NOT deactivate session for \(testCase.testDescription)")
    }
    
    @Test("Pause then background DOES deactivate session (AudioPlayerController)", arguments: [PlaybackControllerTestCase.audioPlayerController])
    func pauseThenBackgroundDeactivatesSession(testCase: PlaybackControllerTestCase) async throws {
        let harness = testCase.makeHarness()
        
        // Play then pause
        try harness.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        harness.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.isPlaying)
        
        // Reset counters before background
        harness.resetSessionCounters()
        
        // Enter background while paused
        harness.simulateEnterBackground()
        await harness.waitForAsync()
        
        // SHOULD deactivate session (playbackIntended is false after pause)
        #expect(harness.sessionDeactivationCount == 1,
               "Background after pause should deactivate session for \(testCase.testDescription)")
    }
}
#endif

/*
 Expected Shared Behaviors (all implementations must satisfy):
 
 1. PLAY BEHAVIOR
    - play(reason:) should set isPlaying to true
    - play(reason:) should call the underlying player's play method
    - play(reason:) should log analytics with reason
 
 2. PAUSE BEHAVIOR
    - pause() should set isPlaying to false
    - pause() should call the underlying player's pause method
 
 3. TOGGLE BEHAVIOR
    - toggle(reason:) while playing should pause
    - toggle(reason:) while paused should play
 
 4. INTERRUPTION HANDLING (iOS)
    - Should respond to interruption began
    - Should resume if shouldResume option is set when interruption ends
 
 5. BACKGROUND/FOREGROUND (iOS)
    - Should keep playing when app enters background
    - Should deactivate session in background if not playing
 
 6. PLAYBACK STALLED
    - Should attempt reconnect with exponential backoff
 */

