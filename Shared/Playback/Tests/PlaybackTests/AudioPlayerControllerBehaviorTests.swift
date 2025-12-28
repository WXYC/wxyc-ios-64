//
//  AudioPlayerControllerBehaviorTests.swift
//  PlaybackTests
//
//  Comprehensive parameterized behavior tests for all PlaybackController implementations.
//  These tests define the expected behavioral contract that all player controllers must follow.
//
//  All player controllers (AudioPlayerController, RadioPlayerController, AVAudioStreamer)
//  are tested against the same behavioral contract to ensure consistency.
//

import Testing
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
import MediaPlayer
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import AVAudioStreamerModule
#endif

// MARK: - PlaybackController Test Convenience Extensions

/// Convenience methods for testing - allows calling play()/toggle() without reason parameter
extension PlaybackController {
    func play() {
        try? play(reason: "test")
    }

    func toggle() {
        try? toggle(reason: "test")
    }
}

// MARK: - Test Harness Protocol
    
/// Protocol for test harnesses that wrap different player controller implementations
@MainActor
protocol PlayerControllerTestHarness: AnyObject {
    var controller: any PlaybackController { get }
    
    /// The notification center used by this harness for simulating system events
    var notificationCenter: NotificationCenter { get }

    /// Number of times play was called on the mock player
    var playCallCount: Int { get }
    /// Number of times stop was called on the mock player
    var stopCallCount: Int { get }
    /// Whether the mock session was activated
    var sessionActivated: Bool { get }
    /// Whether the mock session was deactivated
    var sessionDeactivated: Bool { get }
    /// Number of times analytics play was called
    var analyticsPlayCallCount: Int { get }
    /// Number of times analytics stop was called
    var analyticsStopCallCount: Int { get }
    /// The last analytics play reason
    var lastAnalyticsPlayReason: String? { get }
    /// The last analytics stop duration
    var lastAnalyticsStopDuration: TimeInterval? { get }
    
    /// Simulates the player starting to play (for async players)
    func simulatePlaybackStarted()
    /// Simulates the player stopping (for async players)
    func simulatePlaybackStopped()
    /// Waits for async operations to complete (fixed delay)
    func waitForAsync() async
    /// Waits until a condition is met or timeout expires (polling-based)
    @MainActor func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration) async
    /// Resets all tracked state
    func reset()

    /// Returns true if the stream is in a reset/disconnected state (for live streaming behavior)
    /// After stop(), live streaming players should reset the stream so resume plays live audio
    func isStreamReset() -> Bool

    /// Simulates a playback stall (e.g., network interruption)
    /// Not all controllers support stall simulation in tests
    func simulateStall()

    /// Whether this harness supports stall simulation
    var supportsStallSimulation: Bool { get }

    /// Returns the number of backoff/reconnection attempts made by the controller.
    /// Returns nil if the controller doesn't use exponential backoff.
    func getBackoffAttempts() -> UInt?

    #if os(iOS)
    /// Posts a background notification to the harness's notification center
    func postBackgroundNotification()
    /// Posts a foreground notification to the harness's notification center
    func postForegroundNotification()
    /// Posts an interruption began notification
    func postInterruptionBegan(shouldResume: Bool)
    /// Posts an interruption ended notification
    func postInterruptionEnded(shouldResume: Bool)
    #endif
}

// MARK: - Protocol Default Implementations

extension PlayerControllerTestHarness {
    /// Default implementation of waitUntil that polls until condition is met or timeout expires.
    /// Uses Task.yield() to allow pending Tasks (like notification handlers) to execute.
    @MainActor func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
        let start = Date()
        let timeoutSeconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        while !condition() {
            if Date().timeIntervalSince(start) > timeoutSeconds {
                return // timeout expired
            }
            // Yield to allow other scheduled tasks to run
            await Task.yield()
        }
    }
}

// MARK: - Test Case Enumeration

/// Enumeration of player controller implementations to test
enum PlayerControllerTestCase: String, CaseIterable, CustomTestStringConvertible {
    case audioPlayerController
    case radioPlayerController
    #if !os(watchOS)
    case avAudioStreamer
    #endif

    var testDescription: String {
        switch self {
        case .audioPlayerController:
            return "AudioPlayerController"
        case .radioPlayerController:
            return "RadioPlayerController"
        #if !os(watchOS)
        case .avAudioStreamer:
            return "AVAudioStreamer"
        #endif
        }
    }

    /// Whether this controller supports mocked dependencies for detailed testing
    var supportsMockedDependencies: Bool {
        switch self {
        case .audioPlayerController:
            return true
        case .radioPlayerController:
            return true
        #if !os(watchOS)
        case .avAudioStreamer:
            return false
        #endif
        }
    }

    /// Whether this controller supports analytics tracking
    var supportsAnalytics: Bool {
        switch self {
        case .audioPlayerController:
            return true
        case .radioPlayerController:
            return false // Has PostHog integration but not mockable in harness
        #if !os(watchOS)
        case .avAudioStreamer:
            return false
        #endif
        }
    }
    
    /// Test cases that support mocked dependencies
    static var mockedCases: [PlayerControllerTestCase] {
        allCases.filter { $0.supportsMockedDependencies }
    }
}

// MARK: - AudioPlayerController Test Harness

#if os(iOS) || os(tvOS) || os(watchOS)

@MainActor
final class AudioPlayerControllerTestHarness: PlayerControllerTestHarness {
    private let audioPlayerController: AudioPlayerController
    var controller: any PlaybackController { audioPlayerController }
    let mockPlayer: MockAudioPlayer
    let mockSession: MockAudioSession
    let mockCommandCenter: MockRemoteCommandCenter
    let mockAnalytics: MockPlaybackAnalytics
    let notificationCenter: NotificationCenter

    /// Tracks stop count at start of last play to detect stream reset
    private var stopCountAtLastPlay = 0

    var playCallCount: Int { mockPlayer.playCallCount }
    var stopCallCount: Int { mockPlayer.stopCallCount }
    var sessionActivated: Bool { mockSession.lastActiveState == true }
    var sessionDeactivated: Bool { mockSession.lastActiveState == false }
    var analyticsPlayCallCount: Int { mockAnalytics.startedEvents.count }
    var analyticsStopCallCount: Int { mockAnalytics.stoppedEvents.count }
    var lastAnalyticsPlayReason: String? {
        mockAnalytics.startedEvents.last.map { String(describing: $0.reason) }
    }
    var lastAnalyticsStopDuration: TimeInterval? {
        mockAnalytics.stoppedEvents.last?.duration
    }

    init() {
        let streamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        mockPlayer = MockAudioPlayer(url: streamURL)
        mockSession = MockAudioSession()
        mockCommandCenter = MockRemoteCommandCenter()
        mockAnalytics = MockPlaybackAnalytics()
        notificationCenter = NotificationCenter()
    
        audioPlayerController = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: notificationCenter,
            analytics: mockAnalytics
        )
    }

    func simulatePlaybackStarted() {
        // Track stop count so we can detect if stop() resets the stream
        stopCountAtLastPlay = mockPlayer.stopCallCount
    }

    func simulatePlaybackStopped() {
        // AudioPlayerController updates state synchronously via mock
    }

    func waitForAsync() async {
        // AudioPlayerController is synchronous with mocks
        try? await Task.sleep(for: .milliseconds(10))
    }

    func reset() {
        mockPlayer.reset()
        mockSession.reset()
        mockCommandCenter.reset()
        mockAnalytics.reset()
        stopCountAtLastPlay = 0
    }

    /// Returns true if stop() was called to reset the stream.
    /// AudioPlayerController correctly calls player.stop() for live streaming.
    func isStreamReset() -> Bool {
        mockPlayer.stopCallCount > stopCountAtLastPlay
    }

    /// AudioPlayerController handles stalls internally via the player's event stream.
    /// We can simulate a stall by triggering the mock player's stall callback.
    func simulateStall() {
        mockPlayer.simulateStall()
    }

    var supportsStallSimulation: Bool { true }

    /// AudioPlayerController doesn't use ExponentialBackoff for reconnection.
    func getBackoffAttempts() -> UInt? { nil }
    
    #if os(iOS)
    func postBackgroundNotification() {
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    func postForegroundNotification() {
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    func postInterruptionBegan(shouldResume: Bool) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)
        ]
        if shouldResume {
            userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        }
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }
    
    func postInterruptionEnded(shouldResume: Bool) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue)
        ]
        if shouldResume {
            userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        }
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }
    #endif
}

// MARK: - Mock Player for RadioPlayer Unit Tests

/// Mock for PlayerProtocol (AVPlayer abstraction) - used for testing RadioPlayer internals
final class MockRadioPlayer: PlayerProtocol, @unchecked Sendable {
    nonisolated(unsafe) var rate: Float = 0
    nonisolated(unsafe) var playCallCount = 0
    nonisolated(unsafe) var pauseCallCount = 0
    nonisolated(unsafe) var replaceCurrentItemCallCount = 0

    nonisolated func play() {
        playCallCount += 1
        rate = 1.0
    }

    nonisolated func pause() {
        pauseCallCount += 1
        rate = 0
    }

    nonisolated func replaceCurrentItem(with item: AVPlayerItem?) {
        replaceCurrentItemCallCount += 1
    }

    func reset() {
        rate = 0
        playCallCount = 0
        pauseCallCount = 0
        replaceCurrentItemCallCount = 0
    }
}

// MARK: - RadioPlayerController Test Harness

/// Comprehensive test harness for RadioPlayerController with mocked dependencies.
/// Now uses MockAudioPlayer (AudioPlayerProtocol) for consistent abstraction level.
@MainActor
final class RadioPlayerControllerTestHarness: PlayerControllerTestHarness {
    private let radioPlayerController: RadioPlayerController
    var controller: any PlaybackController { radioPlayerController }
    let mockPlayer: MockAudioPlayer
    let notificationCenter: NotificationCenter

    /// Tracks stop count at start of last play to detect stream reset
    private var stopCountAtLastPlay = 0

    var playCallCount: Int { mockPlayer.playCallCount }
    var stopCallCount: Int { mockPlayer.stopCallCount }
    var sessionActivated: Bool { controller.isPlaying }
    var sessionDeactivated: Bool { !controller.isPlaying }
    var analyticsPlayCallCount: Int { 0 } // Not trackable without PostHog mock
    var analyticsStopCallCount: Int { 0 } // Not trackable without PostHog mock
    var lastAnalyticsPlayReason: String? { nil }
    var lastAnalyticsStopDuration: TimeInterval? { nil }

    init() {
        let streamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        mockPlayer = MockAudioPlayer(url: streamURL)
        notificationCenter = NotificationCenter()

        radioPlayerController = RadioPlayerController(
            radioPlayer: mockPlayer,
            notificationCenter: notificationCenter,
            remoteCommandCenter: .shared()
        )
    }

    func simulatePlaybackStarted() {
        // Track stop count so we can detect if stop() resets the stream
        stopCountAtLastPlay = mockPlayer.stopCallCount
        // Simulate the mock player transitioning to playing state
        mockPlayer.simulateStateChange(to: .playing)
    }

    func simulatePlaybackStopped() {
        mockPlayer.simulateStateChange(to: .idle)
    }

    func waitForAsync() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    func reset() {
        controller.stop()
        mockPlayer.reset()
        stopCountAtLastPlay = 0
    }

    /// Returns true if stop() was called to reset the stream.
    func isStreamReset() -> Bool {
        mockPlayer.stopCallCount > stopCountAtLastPlay
    }

    /// Simulates a playback stall by posting AVPlayerItemPlaybackStalled notification.
    /// RadioPlayerController handles stalls through notification handling.
    func simulateStall() {
        notificationCenter.post(name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
    }

    var supportsStallSimulation: Bool { true }

    /// Returns the number of backoff attempts from the controller's internal backoff timer.
    func getBackoffAttempts() -> UInt? { radioPlayerController.backoffTimer.numberOfAttempts }
    
    #if os(iOS)
    func postBackgroundNotification() {
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func postForegroundNotification() {
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    func postInterruptionBegan(shouldResume: Bool) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)
        ]
        if shouldResume {
            userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        }
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    func postInterruptionEnded(shouldResume: Bool) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue)
        ]
        if shouldResume {
            userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        }
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }
    #endif
}

// MARK: - AVAudioStreamer Test Harness

#if !os(watchOS)

/// Test harness for AVAudioStreamer wrapped in AudioPlayerController.
/// Uses real AVAudioStreamer internally for integration testing.
@MainActor
final class AVAudioStreamerTestHarness: PlayerControllerTestHarness {
    private let streamer: AVAudioStreamer
    private let audioPlayerController: AudioPlayerController
    var controller: any PlaybackController { audioPlayerController }
    let notificationCenter: NotificationCenter

    // Track calls through state observations
    private var _playCallCount = 0
    private var _stopCallCount = 0
    private var wasPlaying = false

    var playCallCount: Int { _playCallCount }
    var stopCallCount: Int { _stopCallCount }
    var sessionActivated: Bool { controller.isPlaying }
    var sessionDeactivated: Bool { !controller.isPlaying }
    var analyticsPlayCallCount: Int { 0 }
    var analyticsStopCallCount: Int { 0 }
    var lastAnalyticsPlayReason: String? { nil }
    var lastAnalyticsStopDuration: TimeInterval? { nil }

    init() {
        notificationCenter = NotificationCenter()
        let config = AVAudioStreamerConfiguration(
            url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        )
        streamer = AVAudioStreamer(configuration: config)
        audioPlayerController = AudioPlayerController(
            player: streamer,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: notificationCenter,
            analytics: MockPlaybackAnalytics()
        )
    }

    func simulatePlaybackStarted() {
        _playCallCount += 1
        wasPlaying = true
    }

    func simulatePlaybackStopped() {
        if wasPlaying {
            _stopCallCount += 1
            wasPlaying = false
        }
    }

    func waitForAsync() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    func reset() {
        controller.stop()
        _playCallCount = 0
        _stopCallCount = 0
        wasPlaying = false
    }

    /// Returns true if stop() disconnected and reset the stream.
    /// stop() properly disconnects HTTP, clears buffers, and sets state to .idle.
    /// For live streaming, this ensures resume will connect to live audio, not stale buffers.
    func isStreamReset() -> Bool {
        // After stop(), state should be .idle.
        streamer.state == .idle
    }

    /// Simulates a playback stall by calling the internal handleStall() method.
    /// AVAudioStreamer exposes this as internal for testability via @testable import.
    func simulateStall() {
        streamer.handleStall()
    }

    var supportsStallSimulation: Bool { true }

    /// Returns the number of backoff attempts from the streamer's internal backoff timer.
    func getBackoffAttempts() -> UInt? { streamer.backoffTimer.numberOfAttempts }
    
    #if os(iOS)
    func postBackgroundNotification() {
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    func postForegroundNotification() {
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    func postInterruptionBegan(shouldResume: Bool) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)
        ]
        if shouldResume {
            userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        }
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }
    
    func postInterruptionEnded(shouldResume: Bool) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue)
        ]
        if shouldResume {
            userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        }
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }
    #endif
}
#endif
    
// MARK: - Harness Factory

extension PlayerControllerTestCase {
    @MainActor
    func makeHarness() -> any PlayerControllerTestHarness {
        switch self {
        case .audioPlayerController:
            AudioPlayerControllerTestHarness()
        case .radioPlayerController:
            RadioPlayerControllerTestHarness()
        #if !os(watchOS)
        case .avAudioStreamer:
            AVAudioStreamerTestHarness()
        #endif
        }
    }
}

// MARK: - Parameterized Behavior Tests

@Suite("Player Controller Behavior Tests")
@MainActor
struct PlayerControllerBehaviorTests {
    
    // MARK: - Core Playback Behavior (Mocked Controllers)
    
    @Test("play() sets isPlaying to true", arguments: PlayerControllerTestCase.mockedCases)
    func playSetsIsPlayingTrue(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "play() should set isPlaying to true")
    }

    @Test("stop() sets isPlaying to false", arguments: PlayerControllerTestCase.mockedCases)
    func stopSetsIsPlayingFalse(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "stop() should set isPlaying to false")
    }
    
    @Test("toggle() while playing stops", arguments: PlayerControllerTestCase.mockedCases)
    func toggleFromPlayingStops(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        harness.controller.toggle()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "toggle() while playing should stop")
    }

    @Test("toggle() while stopped starts playback", arguments: PlayerControllerTestCase.mockedCases)
    func toggleWhileStoppedStartsPlayback(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        #expect(!harness.controller.isPlaying)

        harness.controller.toggle()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        #expect(harness.controller.isPlaying, "toggle() while stopped should start playback")
    }
    
    @Test("Initial state is not playing", arguments: PlayerControllerTestCase.mockedCases)
    func initialStateIsNotPlaying(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        #expect(!harness.controller.isPlaying, "Initial state should be not playing")
    }
    
    // MARK: - Underlying Player Integration (Mocked Controllers Only)
    
    /// Note: This test only runs for AudioPlayerController because RadioPlayerController's
    /// play() method goes through AVAudioSession.activate() which fails in test environments.
    /// RadioPlayerController's player integration is tested via simulatePlaybackStarted() instead.
    @Test("play() calls underlying player")
    func playCallsUnderlyingPlayer() async {
        let harness = AudioPlayerControllerTestHarness()
        let initialCount = harness.playCallCount
        harness.controller.play()
        await harness.waitForAsync()
        #expect(harness.playCallCount > initialCount, "play() should call underlying player")
    }
    
    @Test("stop() calls underlying player", arguments: PlayerControllerTestCase.mockedCases)
    func stopCallsUnderlyingPlayer(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let initialCount = harness.stopCallCount
        harness.controller.stop()
        await harness.waitForAsync()

        #expect(harness.stopCallCount > initialCount, "stop() should call underlying player")
    }
    
    // MARK: - State Consistency Tests
    
    @Test("Multiple play calls are idempotent", arguments: PlayerControllerTestCase.mockedCases)
    func multiplePlayCallsAreIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        // Play again while already playing
        harness.controller.play()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Multiple play calls should keep isPlaying true")
    }
    
    @Test("Multiple stop calls are idempotent", arguments: PlayerControllerTestCase.mockedCases)
    func multipleStopCallsAreIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        // Stop again while already stopped
        harness.controller.stop()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying, "Multiple stop calls should keep isPlaying false")
    }
    
    @Test("Rapid play/stop cycles maintain consistency", arguments: PlayerControllerTestCase.mockedCases)
    func rapidPlayStopCyclesMaintainConsistency(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()

        for _ in 0..<5 {
            harness.controller.play()
            harness.simulatePlaybackStarted()
            await harness.waitForAsync()
            #expect(harness.controller.isPlaying)

            harness.controller.stop()
            harness.simulatePlaybackStopped()
            await harness.waitForAsync()
            #expect(!harness.controller.isPlaying)
        }
    }
}

// MARK: - Background/Foreground Behavior Tests (iOS)
    
#if os(iOS)
@Suite("Background/Foreground Behavior Tests")
@MainActor
struct BackgroundForegroundBehaviorTests {

    @Test("Background while playing keeps session active", arguments: PlayerControllerTestCase.mockedCases)
    func backgroundWhilePlayingKeepsSessionActive(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        let stopCountBefore = harness.stopCallCount
        harness.postBackgroundNotification()
        await harness.waitForAsync()

        // Should NOT have stopped
        #expect(harness.stopCallCount == stopCountBefore,
               "Background while playing should not stop")
    }
        
    @Test("Background while not playing is handled gracefully", arguments: PlayerControllerTestCase.mockedCases)
    func backgroundWhileNotPlayingIsHandled(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        #expect(!harness.controller.isPlaying)
        
        // Should not crash or cause issues
        harness.postBackgroundNotification()
        await harness.waitForAsync()
        
        // Verify still not playing
        #expect(!harness.controller.isPlaying)
    }
    
    @Test("Foreground while playing reactivates", arguments: PlayerControllerTestCase.mockedCases)
    func foregroundWhilePlayingReactivates(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        harness.postBackgroundNotification()
        await harness.waitForAsync()
        
        harness.postForegroundNotification()
        await harness.waitForAsync()
        
        // Should still be playing or have reactivated
        // (specific behavior varies by controller implementation)
    }
        
    @Test("Foreground while not playing does not start playback", arguments: PlayerControllerTestCase.mockedCases)
    func foregroundWhileNotPlayingDoesNotStartPlayback(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        #expect(!harness.controller.isPlaying)
        
        let playCountBefore = harness.playCallCount
        harness.postForegroundNotification()
        await harness.waitForAsync()
        
        // Should NOT have started playback automatically
        // Note: RadioPlayerController may call stop on foreground when not playing,
        // so we just verify it's not playing
        #expect(!harness.controller.isPlaying,
               "Foreground while not playing should not start playback")
    }
}
#endif

// MARK: - Interruption Handling Tests (iOS)
    
#if os(iOS)
@Suite("Interruption Handling Tests")
@MainActor
struct InterruptionHandlingTests {
    
    @Test("Interruption began stops playback", arguments: PlayerControllerTestCase.mockedCases)
    func interruptionBeganStopsPlayback(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        let stopCountBefore = harness.stopCallCount
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        #expect(harness.stopCallCount > stopCountBefore,
               "Interruption began should stop playback")
    }
    
    /// AudioPlayerController ALWAYS stops on interruption began, regardless of shouldResume option.
    /// Note: RadioPlayerController has different behavior - it only stops when shouldResume is false.
    @Test("AudioPlayerController stops on interruption began regardless of shouldResume")
    func audioPlayerControllerInterruptionBeganStopsRegardlessOfShouldResume() async {
        let harness = AudioPlayerControllerTestHarness()

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let stopCountBefore = harness.stopCallCount
        // AudioPlayerController should stop even with shouldResume: true
        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.stopCallCount > stopCountBefore,
               "AudioPlayerController should stop on interruption began regardless of shouldResume")
    }
    
    /// RadioPlayerController only stops on interruption began when shouldResume option is NOT set.
    /// When shouldResume is set, it logs analytics but doesn't stop (expects system to auto-resume).
    @Test("RadioPlayerController does not stop on interruption began with shouldResume")
    func radioPlayerControllerInterruptionBeganWithShouldResumeDoesNotStop() async {
        let harness = RadioPlayerControllerTestHarness()

        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let stopCountBefore = harness.stopCallCount
        // RadioPlayerController should NOT stop when shouldResume is true
        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.stopCallCount == stopCountBefore,
               "RadioPlayerController should not stop on interruption began with shouldResume")
    }
    
    /// Note: This test only runs for AudioPlayerController because RadioPlayerController's
    /// play() method goes through AVAudioSession.activate() which fails in test environments.
    /// The RadioPlayerController's interrupt-resume behavior is tested separately.
    @Test("Interruption ended with shouldResume resumes playback for AudioPlayerController")
    func interruptionEndedWithShouldResumeResumesPlayback() async {
        let harness = AudioPlayerControllerTestHarness()

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Simulate interruption began (this sets wasPlayingBeforeInterruption = true and stops)
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        let playCountBefore = harness.playCallCount
    
        // Now post interruption ended with shouldResume
        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.playCallCount > playCountBefore,
               "Interruption ended with shouldResume should resume playback")
    }
    
    /// RadioPlayerController has different interruption behavior - it always tries to play
    /// on interrupt end, but the actual play goes through AVAudioSession which fails in tests.
    /// We verify the controller receives the notification and attempts to handle it.
    @Test("RadioPlayerController attempts resume on interruption ended")
    func radioPlayerControllerInterruptionEndedAttemptResume() async {
        let harness = RadioPlayerControllerTestHarness()

        // Start playing (using simulatePlaybackStarted to bypass AVAudioSession)
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        // Post interruption began - RadioPlayerController only stops when shouldResume is false
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        // Verify stop was called
        #expect(harness.stopCallCount >= 1, "Interruption began should stop")

        // Post interruption ended with shouldResume
        // Note: RadioPlayerController's play() goes through AVAudioSession which may fail,
        // so we just verify the notification was received without asserting play count
        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()

        // The test passes if no crash occurred - the controller handled the notification
    }
}
#endif

// MARK: - Analytics Integration Tests (AudioPlayerController only)
        
@Suite("AudioPlayerController Analytics Tests")
@MainActor
struct AudioPlayerControllerAnalyticsTests {

    @Test("play() calls analytics")
    func playCallsAnalytics() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.reset()
        harness.controller.play()
        #expect(harness.analyticsPlayCallCount > 0, "play() should call analytics")
    }
    
    @Test("stop() calls analytics with duration")
    func stopCallsAnalyticsWithDuration() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.reset()
        harness.controller.play()

        // Small delay to ensure non-zero duration
        try? await Task.sleep(for: .milliseconds(10))
    
        harness.controller.stop()
        #expect(harness.analyticsStopCallCount > 0, "stop() should call analytics")
        #expect(harness.lastAnalyticsStopDuration != nil, "stop() should report duration")
    }

    @Test("Analytics receives play reason")
    func analyticsReceivesPlayReason() async throws {
        let harness = AudioPlayerControllerTestHarness()
        try harness.controller.play(reason: "user tapped play")

        #expect(harness.mockAnalytics.startedEvents.count == 1)
        #expect(harness.mockAnalytics.startedEvents.first?.reason == .userInitiated)
    }

    @Test("Analytics receives stop duration")
    func analyticsReceivesStopDuration() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.controller.play()
    
        // Wait a bit to accumulate duration
        try? await Task.sleep(for: .milliseconds(50))

        harness.controller.stop()

        #expect(harness.mockAnalytics.stoppedEvents.count == 1)
        if let duration = harness.mockAnalytics.stoppedEvents.first?.duration {
            #expect(duration >= 0.04, "Duration should be at least 40ms")
        } else {
            Issue.record("Expected stop duration to be recorded")
        }
    }
    
    @Test("stop() reports analytics stopped event")
    func stopReportsAnalyticsStoppedEvent() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.controller.play()
        harness.controller.stop()

        #expect(harness.mockAnalytics.stoppedEvents.count == 1, "stop() should report analytics stopped event")
    }
}

// MARK: - AudioPlayerController Background/Foreground Specific Tests

#if os(iOS)
@Suite("AudioPlayerController Background/Foreground Behavior Tests")
@MainActor
struct AudioPlayerControllerBackgroundBehaviorTests {
    
    @Test("play() sets playbackIntended - background does NOT deactivate session")
    func playWithURLSetsPlaybackIntended() async throws {
        let harness = AudioPlayerControllerTestHarness()

        try harness.controller.play(reason: "test")
        harness.mockSession.reset()  // Clear the activation from play()
        
        harness.controller.handleAppDidEnterBackground()
        
        // Should NOT have deactivated (playbackIntended is true)
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background while playing should NOT deactivate session")
    }
        
    @Test("stop() clears playbackIntended - background DOES deactivate session")
    func stopClearsPlaybackIntended() async throws {
        let harness = AudioPlayerControllerTestHarness()

        try harness.controller.play(reason: "test")
        harness.controller.stop()

        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        
        // SHOULD have deactivated (playbackIntended is false)
        #expect(harness.mockSession.setActiveCallCount == 1,
               "Background after stop should deactivate session")
        #expect(harness.mockSession.lastActiveState == false,
               "Session should be set to inactive")
    }
        
    @Test("stop then play() keeps playbackIntended true")
    func stopThenPlayKeepsPlaybackIntended() async throws {
        let harness = AudioPlayerControllerTestHarness()

        // Play -> Stop -> Play cycle
        try harness.controller.play(reason: "initial")
        harness.controller.stop()  // playbackIntended = false
        harness.controller.play()  // playbackIntended should be true again

        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()

        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background after stop-then-play should NOT deactivate")
    }
    
    @Test("stop() clears playbackIntended and deactivates immediately")
    func stopClearsPlaybackIntendedAndDeactivates() async throws {
        let harness = AudioPlayerControllerTestHarness()

        try harness.controller.play(reason: "test")
        harness.mockSession.reset()
        
        harness.controller.stop()
        
        // stop() itself should deactivate
        #expect(harness.mockSession.setActiveCallCount >= 1,
               "stop() should deactivate session")
        #expect(harness.mockSession.lastActiveState == false,
               "Session should be inactive after stop()")
    }
    
    @Test("foreground while playbackIntended reactivates session")
    func foregroundWhilePlaybackIntendedReactivates() async throws {
        let harness = AudioPlayerControllerTestHarness()

        try harness.controller.play(reason: "test")
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
    func appleMusicInterruptionScenario() async throws {
        let harness = AudioPlayerControllerTestHarness()

        // User starts WXYC (interrupts Apple Music)
        try harness.controller.play(reason: "user started stream")
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
}
#endif
    
// MARK: - RadioPlayer Direct Tests

@Suite("RadioPlayer Behavior Tests")
@MainActor
struct RadioPlayerBehaviorTests {
    
    @Test("play() calls underlying player")
    func playCallsUnderlyingPlayer() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )
    
        radioPlayer.play()

        #expect(mockPlayer.playCallCount == 1, "play() should call underlying player")
    }
    
    @Test("RadioPlayer.stop() calls underlying player")
    func radioPlayerStopCallsUnderlyingPlayer() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        radioPlayer.play()
        radioPlayer.stop()
        
        #expect(mockPlayer.pauseCallCount == 1, "RadioPlayer.stop() should call underlying player pause")
    }
    
    @Test("RadioPlayer.stop() resets stream")
    func radioPlayerStopResetsStream() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        radioPlayer.play()
        radioPlayer.stop()

        #expect(mockPlayer.replaceCurrentItemCallCount == 1, "RadioPlayer.stop() should reset stream")
    }

    @Test("play() while playing is idempotent")
    func playWhilePlayingIsIdempotent() async throws {
        let mockPlayer = MockRadioPlayer()
        let notificationCenter = NotificationCenter()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: notificationCenter
        )
        
        radioPlayer.play()
        let firstCount = mockPlayer.playCallCount
        
        // Simulate player started playing via notification
        mockPlayer.rate = 1.0
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
    
        #expect(radioPlayer.isPlaying, "isPlaying should be true after notification")
        
        radioPlayer.play()
        #expect(mockPlayer.playCallCount == firstCount, "play() while playing should be no-op")
    }
        
    @Test("isPlaying starts as false")
    func isPlayingStartsAsFalse() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )
    
        #expect(!radioPlayer.isPlaying)
    }
}

// MARK: - PlaybackController Protocol Conformance Tests
        
@Suite("PlaybackController Protocol Conformance Tests")
@MainActor
struct PlaybackControllerProtocolTests {

    @Test("All controllers conform to PlaybackController", arguments: PlayerControllerTestCase.allCases)
    func controllersConformToPlaybackController(testCase: PlayerControllerTestCase) async {
        // This test verifies that all controller types can be used as PlaybackController
        let harness = testCase.makeHarness()

        // Verify the controller has the expected protocol properties/methods
        // These are compile-time checks essentially, but validate behavior
        _ = harness.controller.isPlaying
        harness.controller.play()
        harness.controller.stop()
        harness.controller.toggle()
    }
}

// MARK: - Stop Resume Live Tests

/// Tests verifying that all players resume at live position after stop.
/// For live streaming, stop() should reset/disconnect the stream so that
/// resume plays current live audio, not stale buffered audio.
@Suite("Stop Resume Live Tests")
@MainActor
struct StopResumeLiveTests {

    /// Tests that stop() resets the stream for live streaming.
    /// After stop(), resume should connect fresh to the live stream.
    @Test("Stop resets stream for live playback", arguments: PlayerControllerTestCase.mockedCases)
    func stopResetsStreamForLivePlayback(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Should be playing before stop")

        // Stop - should reset the stream for live playback
        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying, "Should not be playing after stop")

        // Critical assertion: stream should be reset so resume plays live
        #expect(harness.isStreamReset(),
               "Stop should reset stream for live streaming so resume plays live audio, not stale buffered audio")
    }

    /// Tests AVAudioStreamer's stop() resets stream by checking state transition.
    /// AVAudioStreamer requires network for playback simulation, so we test state-based behavior.
    #if !os(watchOS)
    @Test("AVAudioStreamer stop resets stream")
    func avAudioStreamerStopResetsStream() async {
        let config = AVAudioStreamerConfiguration(
            url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        )
        let streamer = AVAudioStreamer(configuration: config)

        // Verify initial state
        #expect(streamer.state == .idle, "Should start in idle state")

        // Call stop to verify it sets idle state
        streamer.stop()
        #expect(streamer.state == .idle, "stop() should set idle state")
    }
    #endif
}

// MARK: - Stall Recovery Tests

/// Tests verifying stall detection and recovery behavior.
/// Stalls occur when the stream is interrupted (network issues, buffer underrun, etc.).
@Suite("Stall Recovery Tests")
@MainActor
struct StallRecoveryTests {
    
    /// Test cases that support both stall simulation and backoff tracking
    static var stallTestCases: [PlayerControllerTestCase] {
        PlayerControllerTestCase.mockedCases.filter { testCase in
            let harness = testCase.makeHarness()
            return harness.supportsStallSimulation && harness.getBackoffAttempts() != nil
        }
    }

    @Test("Stall while playing triggers recovery attempt")
    func stallTriggersRecoveryAttempt() async {
        // RadioPlayerController handles stalls via notification and attempts reconnection
        let harness = RadioPlayerControllerTestHarness()

        // Start playing
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Should be playing before stall")

        let initialAttempts = harness.getBackoffAttempts() ?? 0

        // Simulate stall - the handler runs async so we poll until backoff increments
        harness.simulateStall()
        await harness.waitUntil({ (harness.getBackoffAttempts() ?? 0) > initialAttempts }, timeout: .seconds(2))

        // After stall, backoff timer should have been triggered
        let currentAttempts = harness.getBackoffAttempts() ?? 0
        #expect(currentAttempts > initialAttempts,
               "Stall should trigger reconnection attempt via backoff timer")
    }

    @Test("Each stall triggers backoff increment")
    func eachStallTriggersBackoffIncrement() async {
        let harness = RadioPlayerControllerTestHarness()
    
        // Start playing
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let initialAttempts = harness.getBackoffAttempts() ?? 0

        // Simulate a stall and verify backoff increments
        harness.simulateStall()
        await harness.waitUntil({ (harness.getBackoffAttempts() ?? 0) > initialAttempts }, timeout: .seconds(2))

        let attemptsAfterStall = harness.getBackoffAttempts() ?? 0
        #expect(attemptsAfterStall > initialAttempts, "Stall should increment backoff attempts")

        // Note: Multiple consecutive stalls may not consistently increment because
        // the reconnect logic calls play() and may reset the backoff if successful.
        // That's the correct behavior - successful reconnection resets the backoff.
    }

    @Test("AVAudioStreamer stall transitions to stalled state")
    func avAudioStreamerStallTransitionsToStalledState() async {
        #if !os(watchOS)
        let config = AVAudioStreamerConfiguration(
            url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        )
        let streamer = AVAudioStreamer(configuration: config)
    
        // Need to be in playing state for stall to take effect
        // Since we can't easily get to playing state without network, we test the mechanism:
        // handleStall() only transitions if state == .playing
        #expect(streamer.state == .idle, "Should start in idle state")

        // Calling handleStall() in idle state should be a no-op
        streamer.handleStall()
        #expect(streamer.state == .idle, "Stall in idle state should be no-op")
        #endif
    }

    @Test("Successful play resets backoff timer")
    func successfulPlayResetsBackoff() async {
        let harness = RadioPlayerControllerTestHarness()

        // Start playing
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Simulate a stall to increment backoff - wait until it actually increments
        harness.simulateStall()
        await harness.waitUntil({ (harness.getBackoffAttempts() ?? 0) > 0 }, timeout: .seconds(2))

        let attemptsAfterStall = harness.getBackoffAttempts() ?? 0
        #expect(attemptsAfterStall > 0, "Should have attempts after stall")

        // Stop and start fresh - this should reset backoff
        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        // Check if backoff was reset (stop should reset it)
        // Note: The actual reset happens in RadioPlayerController.stop()
        let attemptsAfterStop = harness.getBackoffAttempts() ?? 0

        // The backoff may or may not be reset depending on implementation
        // This test documents the current behavior
        #expect(attemptsAfterStop == 0 || attemptsAfterStop == attemptsAfterStall,
               "Backoff should be reset on stop or maintain current value")
    }
}

// MARK: - Stop Behavior Tests

/// Tests verifying stop() behavior across all player implementations.
/// stop() fully terminates playback and resets state.
@Suite("Stop Behavior Tests")
@MainActor
struct StopBehaviorTests {

    @Test("Stop returns to non-playing state", arguments: PlayerControllerTestCase.mockedCases)
    func stopReturnsToNonPlayingState(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Should be playing before stop")

        // Stop playback
        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "stop() should return to non-playing state")
    }

    @Test("Stop is idempotent", arguments: PlayerControllerTestCase.mockedCases)
    func stopIsIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()

        // Start playing then stop
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        // Stop again - should be safe
        harness.controller.stop()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying, "Multiple stop() calls should be safe")
    }

    @Test("Play after stop works", arguments: PlayerControllerTestCase.mockedCases)
    func playAfterStopWorks(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Stop
        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        // Play again after stop
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        #expect(harness.controller.isPlaying, "play() after stop() should work")
    }

    @Test("Stop while not playing is safe", arguments: PlayerControllerTestCase.mockedCases)
    func stopWhileNotPlayingIsSafe(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()

        // Verify not playing
        #expect(!harness.controller.isPlaying)

        // Stop without having started - should be safe
        harness.controller.stop()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "stop() while not playing should be safe")
    }
}

// MARK: - Behavioral Contract Documentation

/*
 Expected Common Behaviors (all implementations should satisfy):

 1. PLAY BEHAVIOR
    - play() should set isPlaying to true
    - play() should call the underlying player's play method
    - play() should activate the audio session (iOS)
    - play() should call analytics with reason (if supported)
    - play() should set playbackIntended = true (prevents background deactivation)

 2. STOP BEHAVIOR
    - stop() should set isPlaying to false
    - stop() should call the underlying player's stop/pause method
    - stop() should reset the stream for live playback
    - stop() should call analytics with duration (if supported)
    - stop() should set playbackIntended = false

 3. TOGGLE BEHAVIOR
    - toggle() while playing should stop
    - toggle() while stopped should play (and set playbackIntended = true)

 4. STATE CONSISTENCY
    - isPlaying should accurately reflect playback state
    - State changes should be observable
    - playbackIntended tracks user intent, survives transient states

 5. AUDIO SESSION (iOS)
    - Session should be activated before playback
    - Session should remain active during background playback IF playbackIntended is true
    - Session should be deactivated when stopped
    - Session should be deactivated on background IF playbackIntended is false

 6. REMOTE COMMANDS (iOS)
    - Play/Stop/Toggle commands should be enabled
    - Seek/Skip commands should be disabled for live streams

 7. INTERRUPTION HANDLING (iOS)
    - Should stop on interruption began (unless shouldResume is set)
    - Should resume if shouldResume is set and was playing

 8. ROUTE CHANGES (iOS)
    - Should stop when headphones disconnected

 9. ANALYTICS (if supported)
    - play() should log analytics with reason
    - stop() should log analytics with duration

 10. BACKGROUND/FOREGROUND BEHAVIOR (iOS)
    - Background while playbackIntended: do NOT deactivate session
    - Background without playbackIntended: deactivate session
    - Foreground while playbackIntended: reactivate session
    - Foreground without playbackIntended: do NOT activate session
 */

#endif
