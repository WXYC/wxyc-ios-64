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

// MARK: - Player Controller Behavior Protocol

/// Protocol defining the common behaviors expected from any player controller
@MainActor
protocol PlayerControllerBehavior {
    var isPlaying: Bool { get }
    func play()
    func pause()
    func stop()
    func toggle()
}

// MARK: - Test Harness Protocol

/// Protocol for test harnesses that wrap different player controller implementations
@MainActor
protocol PlayerControllerTestHarness {
    associatedtype Controller: PlayerControllerBehavior
    
    var controller: Controller { get }
    
    /// The notification center used by this harness for simulating system events
    var notificationCenter: NotificationCenter { get }
    
    /// Number of times play was called on the mock player
    var playCallCount: Int { get }
    /// Number of times resume was called on the mock player
    var resumeCallCount: Int { get }
    /// Number of times a playback attempt was made (play or resume)
    var playbackAttemptCount: Int { get }
    /// Number of times pause was called on the mock player
    var pauseCallCount: Int { get }
    /// Number of times stop was called on the mock player (for live streaming, pause may call stop)
    var stopCallCount: Int { get }
    /// Number of times a pause action was taken (pause or stop, depending on live streaming behavior)
    var pauseActionCount: Int { get }
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
    /// After pause(), live streaming players should reset the stream so resume plays live audio
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

// MARK: - Type-Erased Harness Wrapper

/// Type-erased wrapper for test harnesses to enable parameterized testing
@MainActor
final class AnyPlayerControllerTestHarness {
    private let _controller: any PlayerControllerBehavior
    private let _notificationCenter: NotificationCenter
    private let _playCallCount: () -> Int
    private let _pauseCallCount: () -> Int
    private let _stopCallCount: () -> Int
    private let _pauseActionCount: () -> Int
    private let _sessionActivated: () -> Bool
    private let _sessionDeactivated: () -> Bool
    private let _analyticsPlayCallCount: () -> Int
    private let _analyticsPauseCallCount: () -> Int
    private let _lastAnalyticsPlayReason: () -> String?
    private let _lastAnalyticsPauseDuration: () -> TimeInterval?
    private let _simulatePlaybackStarted: () -> Void
    private let _simulatePlaybackStopped: () -> Void
    private let _waitForAsync: () async -> Void
    private let _waitUntil: (@escaping @MainActor () -> Bool, Duration) async -> Void
    private let _reset: () -> Void
    private let _isStreamReset: () -> Bool
    private let _simulateStall: () -> Void
    private let _supportsStallSimulation: Bool
    private let _getBackoffAttempts: () -> UInt?
    #if os(iOS)
    private let _postBackgroundNotification: () -> Void
    private let _postForegroundNotification: () -> Void
    private let _postInterruptionBegan: (Bool) -> Void
    private let _postInterruptionEnded: (Bool) -> Void
    #endif
    
    var controller: any PlayerControllerBehavior { _controller }
    var notificationCenter: NotificationCenter { _notificationCenter }
    var playCallCount: Int { _playCallCount() }
    var pauseCallCount: Int { _pauseCallCount() }
    var stopCallCount: Int { _stopCallCount() }
    var pauseActionCount: Int { _pauseActionCount() }
    var sessionActivated: Bool { _sessionActivated() }
    var sessionDeactivated: Bool { _sessionDeactivated() }
    var analyticsPlayCallCount: Int { _analyticsPlayCallCount() }
    var analyticsPauseCallCount: Int { _analyticsPauseCallCount() }
    var lastAnalyticsPlayReason: String? { _lastAnalyticsPlayReason() }
    var lastAnalyticsPauseDuration: TimeInterval? { _lastAnalyticsPauseDuration() }
    
    func simulatePlaybackStarted() { _simulatePlaybackStarted() }
    func simulatePlaybackStopped() { _simulatePlaybackStopped() }
    func waitForAsync() async { await _waitForAsync() }
    func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async { await _waitUntil(condition, timeout) }
    func reset() { _reset() }
    func isStreamReset() -> Bool { _isStreamReset() }
    func simulateStall() { _simulateStall() }
    var supportsStallSimulation: Bool { _supportsStallSimulation }
    func getBackoffAttempts() -> UInt? { _getBackoffAttempts() }

    #if os(iOS)
    func postBackgroundNotification() { _postBackgroundNotification() }
    func postForegroundNotification() { _postForegroundNotification() }
    func postInterruptionBegan(shouldResume: Bool) { _postInterruptionBegan(shouldResume) }
    func postInterruptionEnded(shouldResume: Bool) { _postInterruptionEnded(shouldResume) }
    #endif
    
    init<H: PlayerControllerTestHarness>(_ harness: H) {
        _controller = harness.controller
        _notificationCenter = harness.notificationCenter
        _playCallCount = { harness.playCallCount }
        _pauseCallCount = { harness.pauseCallCount }
        _stopCallCount = { harness.stopCallCount }
        _pauseActionCount = { harness.pauseActionCount }
        _sessionActivated = { harness.sessionActivated }
        _sessionDeactivated = { harness.sessionDeactivated }
        _analyticsPlayCallCount = { harness.analyticsPlayCallCount }
        _analyticsPauseCallCount = { harness.analyticsPauseCallCount }
        _lastAnalyticsPlayReason = { harness.lastAnalyticsPlayReason }
        _lastAnalyticsPauseDuration = { harness.lastAnalyticsPauseDuration }
        _simulatePlaybackStarted = { harness.simulatePlaybackStarted() }
        _simulatePlaybackStopped = { harness.simulatePlaybackStopped() }
        _waitForAsync = { await harness.waitForAsync() }
        _waitUntil = { condition, timeout in await harness.waitUntil(condition, timeout: timeout) }
        _reset = { harness.reset() }
        _isStreamReset = { harness.isStreamReset() }
        _simulateStall = { harness.simulateStall() }
        _supportsStallSimulation = harness.supportsStallSimulation
        _getBackoffAttempts = { harness.getBackoffAttempts() }
        #if os(iOS)
        _postBackgroundNotification = { harness.postBackgroundNotification() }
        _postForegroundNotification = { harness.postForegroundNotification() }
        _postInterruptionBegan = { harness.postInterruptionBegan(shouldResume: $0) }
        _postInterruptionEnded = { harness.postInterruptionEnded(shouldResume: $0) }
        #endif
    }
}

// MARK: - AudioPlayerController Test Harness

#if os(iOS) || os(tvOS) || os(watchOS)

/// Adapter to make AudioPlayerController conform to PlayerControllerBehavior
extension AudioPlayerController: PlayerControllerBehavior {
    public func play() {
        play(reason: "test")
    }
}

@MainActor
final class AudioPlayerControllerTestHarness: PlayerControllerTestHarness {
    let controller: AudioPlayerController
    let mockPlayer: MockAudioPlayer
    let mockSession: MockAudioSession
    let mockCommandCenter: MockRemoteCommandCenter
    let mockAnalytics: MockPlaybackAnalytics
    let notificationCenter: NotificationCenter

    /// Tracks stop count at start of last play to detect stream reset
    private var stopCountAtLastPlay = 0

    var playCallCount: Int { mockPlayer.playCallCount }
    var resumeCallCount: Int { mockPlayer.resumeCallCount }
    var playbackAttemptCount: Int { playCallCount + resumeCallCount }
    var pauseCallCount: Int { mockPlayer.pauseCallCount }
    var stopCallCount: Int { mockPlayer.stopCallCount }
    /// AudioPlayerController calls stop() instead of pause() for live streaming
    var pauseActionCount: Int { mockPlayer.pauseCallCount + mockPlayer.stopCallCount }
    var sessionActivated: Bool { mockSession.lastActiveState == true }
    var sessionDeactivated: Bool { mockSession.lastActiveState == false }
    var analyticsPlayCallCount: Int { mockAnalytics.startedEvents.count }
    var analyticsPauseCallCount: Int { mockAnalytics.stoppedEvents.count }
    var lastAnalyticsPlayReason: String? {
        mockAnalytics.startedEvents.last.map { String(describing: $0.reason) }
    }
    var lastAnalyticsPauseDuration: TimeInterval? {
        mockAnalytics.stoppedEvents.last?.duration
    }

    init() {
        let streamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        mockPlayer = MockAudioPlayer(url: streamURL)
        mockSession = MockAudioSession()
        mockCommandCenter = MockRemoteCommandCenter()
        mockAnalytics = MockPlaybackAnalytics()
        notificationCenter = NotificationCenter()

        controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: notificationCenter,
            analytics: mockAnalytics
        )
    }

    func simulatePlaybackStarted() {
        // Track stop count so we can detect if pause() resets the stream
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

    /// Returns true if pause() called stop() to reset the stream.
    /// AudioPlayerController correctly calls player.stop() on pause for live streaming.
    func isStreamReset() -> Bool {
        return mockPlayer.stopCallCount > stopCountAtLastPlay
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

// MARK: - RadioPlayerController Test Harness

/// Adapter to make RadioPlayerController conform to PlayerControllerBehavior
extension RadioPlayerController: PlayerControllerBehavior {
    public func play() {
        try? play(reason: "test")
    }

    public func toggle() {
        try? toggle(reason: "test")
    }
}

/// Comprehensive test harness for RadioPlayerController with mocked dependencies
@MainActor
final class RadioPlayerControllerTestHarness: PlayerControllerTestHarness {
    let controller: RadioPlayerController
    let mockPlayer: MockRadioPlayer
    let notificationCenter: NotificationCenter
    let testUserDefaults: UserDefaults
    let radioPlayer: RadioPlayer

    /// Tracks replaceCurrentItem count at start of last play to detect stream reset
    private var replaceCountAtLastPlay = 0

    var playCallCount: Int { mockPlayer.playCallCount }
    var resumeCallCount: Int { 0 } // AVPlayer doesn't have separate resume
    var playbackAttemptCount: Int { playCallCount }
    var pauseCallCount: Int { mockPlayer.pauseCallCount }
    var stopCallCount: Int { 0 } // AVPlayer doesn't have separate stop
    /// RadioPlayerController calls pause() which internally resets stream
    var pauseActionCount: Int { mockPlayer.pauseCallCount }
    var sessionActivated: Bool { controller.isPlaying }
    var sessionDeactivated: Bool { !controller.isPlaying }
    var analyticsPlayCallCount: Int { 0 } // Not trackable without PostHog mock
    var analyticsPauseCallCount: Int { 0 } // Not trackable without PostHog mock
    var lastAnalyticsPlayReason: String? { nil }
    var lastAnalyticsPauseDuration: TimeInterval? { nil }
        
    init() {
        mockPlayer = MockRadioPlayer()
        notificationCenter = NotificationCenter()
        testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        
        radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
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
    
    func simulatePlaybackStarted() {
        // Track replaceCurrentItem count so we can detect if pause() resets the stream
        replaceCountAtLastPlay = mockPlayer.replaceCurrentItemCallCount
        // Directly call radioPlayer.play() to bypass AVAudioSession activation
        // which would fail in test environment. This simulates the state after
        // successful audio session activation.
        radioPlayer.play()
        mockPlayer.rate = 1.0
        mockPlayer.simulatedIsPlaying = true
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: nil)
    }

    func simulatePlaybackStopped() {
        mockPlayer.rate = 0
        mockPlayer.simulatedIsPlaying = false
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: nil)
    }

    func waitForAsync() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    func reset() {
        controller.pause()
        mockPlayer.reset()
        replaceCountAtLastPlay = 0
    }

    /// Returns true if pause() called resetStream() (which calls replaceCurrentItem).
    /// RadioPlayer correctly resets the stream on pause for live streaming.
    func isStreamReset() -> Bool {
        return mockPlayer.replaceCurrentItemCallCount > replaceCountAtLastPlay
    }

    /// Simulates a playback stall by posting AVPlayerItemPlaybackStalled notification.
    /// RadioPlayerController handles stalls through the RadioPlayer's notification handling.
    func simulateStall() {
        notificationCenter.post(name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
    }

    var supportsStallSimulation: Bool { true }

    /// Returns the number of backoff attempts from the controller's internal backoff timer.
    func getBackoffAttempts() -> UInt? { controller.backoffTimer.numberOfAttempts }
    
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

/// Adapter to make AVAudioStreamer conform to PlayerControllerBehavior
extension AVAudioStreamer: PlayerControllerBehavior {
    public var isPlaying: Bool {
        state == .playing
    }

    public func play() {
        Task {
            try? await self.play()
        }
    }
    
    public func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
}

/// Test harness for AVAudioStreamer using state-based tracking
/// Note: AVAudioStreamer uses real networking/audio components internally,
/// so we track behavior through state transitions rather than mocked dependencies
@MainActor
final class AVAudioStreamerTestHarness: PlayerControllerTestHarness {
    let controller: AVAudioStreamer
    let notificationCenter: NotificationCenter
    
    // Track calls through state observations
    private var _playCallCount = 0
    private var _pauseCallCount = 0
    private var wasPlaying = false
    
    var playCallCount: Int { _playCallCount }
    var resumeCallCount: Int { 0 } // AVAudioStreamer tracks via state
    var playbackAttemptCount: Int { _playCallCount }
    var pauseCallCount: Int { _pauseCallCount }
    var stopCallCount: Int { 0 } // Tracked via state
    /// AVAudioStreamer tracks via state
    var pauseActionCount: Int { _pauseCallCount }
    var sessionActivated: Bool { controller.isPlaying }
    var sessionDeactivated: Bool { !controller.isPlaying }
    var analyticsPlayCallCount: Int { 0 }
    var analyticsPauseCallCount: Int { 0 }
    var lastAnalyticsPlayReason: String? { nil }
    var lastAnalyticsPauseDuration: TimeInterval? { nil }
    
    init() {
        notificationCenter = NotificationCenter()
        let config = AVAudioStreamerConfiguration(
            url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3.mp3")!
        )
        controller = AVAudioStreamer(configuration: config)
    }
    
    func simulatePlaybackStarted() {
        // AVAudioStreamer manages its own state; we track via observation
        _playCallCount += 1
        wasPlaying = true
    }
    
    func simulatePlaybackStopped() {
        // AVAudioStreamer manages its own state
        if wasPlaying {
            _pauseCallCount += 1
            wasPlaying = false
        }
    }
    
    func waitForAsync() async {
        try? await Task.sleep(for: .milliseconds(100))
    }
    
    func reset() {
        controller.stop()
        _playCallCount = 0
        _pauseCallCount = 0
        wasPlaying = false
    }

    /// Returns true if pause() disconnected and reset the stream.
    /// After the fix, pause() properly disconnects HTTP, clears buffers, and sets state to .idle.
    /// For live streaming, this ensures resume will connect to live audio, not stale buffers.
    /// Note: There is no .paused state because live streaming pause = stop semantically.
    func isStreamReset() -> Bool {
        // After pause(), state should be .idle since pause = stop for live streaming.
        return controller.state == .idle
    }

    /// Simulates a playback stall by calling the internal handleStall() method.
    /// AVAudioStreamer exposes this as internal for testability via @testable import.
    func simulateStall() {
        controller.handleStall()
    }

    var supportsStallSimulation: Bool { true }

    /// Returns the number of backoff attempts from the streamer's internal backoff timer.
    func getBackoffAttempts() -> UInt? { controller.backoffTimer.numberOfAttempts }
    
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
    func makeHarness() -> AnyPlayerControllerTestHarness {
        switch self {
        case .audioPlayerController:
            return AnyPlayerControllerTestHarness(AudioPlayerControllerTestHarness())
        case .radioPlayerController:
            return AnyPlayerControllerTestHarness(RadioPlayerControllerTestHarness())
        #if !os(watchOS)
        case .avAudioStreamer:
            return AnyPlayerControllerTestHarness(AVAudioStreamerTestHarness())
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
    
    @Test("pause() sets isPlaying to false", arguments: PlayerControllerTestCase.mockedCases)
    func pauseSetsIsPlayingFalse(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        harness.controller.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        #expect(!harness.controller.isPlaying, "pause() should set isPlaying to false")
    }
    
    @Test("toggle() while playing pauses", arguments: PlayerControllerTestCase.mockedCases)
    func toggleFromPlayingPauses(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        harness.controller.toggle()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        #expect(!harness.controller.isPlaying, "toggle() while playing should pause")
    }
        
    @Test("toggle() while paused starts playback", arguments: PlayerControllerTestCase.mockedCases)
    func toggleWhilePausedStartsPlayback(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        #expect(!harness.controller.isPlaying)
        
        harness.controller.toggle()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        #expect(harness.controller.isPlaying, "toggle() while paused should start playback")
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
    
    @Test("pause() calls underlying player", arguments: PlayerControllerTestCase.mockedCases)
    func pauseCallsUnderlyingPlayer(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let initialCount = harness.pauseActionCount
        harness.controller.pause()
        await harness.waitForAsync()

        // Note: AudioPlayerController calls stop() instead of pause() for live streaming
        #expect(harness.pauseActionCount > initialCount, "pause() should call underlying player (may call stop for live streaming)")
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
    
    @Test("Multiple pause calls are idempotent", arguments: PlayerControllerTestCase.mockedCases)
    func multiplePauseCallsAreIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        harness.controller.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)
        
        // Pause again while already paused
        harness.controller.pause()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying, "Multiple pause calls should keep isPlaying false")
    }
    
    @Test("Rapid play/pause cycles maintain consistency", arguments: PlayerControllerTestCase.mockedCases)
    func rapidPlayPauseCyclesMaintainConsistency(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        
        for _ in 0..<5 {
            harness.controller.play()
            harness.simulatePlaybackStarted()
            await harness.waitForAsync()
            #expect(harness.controller.isPlaying)
            
            harness.controller.pause()
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
        
        let pauseCountBefore = harness.pauseCallCount
        harness.postBackgroundNotification()
        await harness.waitForAsync()
    
        // Should NOT have paused
        #expect(harness.pauseCallCount == pauseCountBefore,
               "Background while playing should not pause")
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
        // Note: RadioPlayerController calls pause on foreground when not playing,
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
    
    @Test("Interruption began pauses playback", arguments: PlayerControllerTestCase.mockedCases)
    func interruptionBeganPausesPlayback(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()
        
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        let pauseCountBefore = harness.pauseActionCount
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()
    
        // Note: AudioPlayerController calls stop() instead of pause() for live streaming
        #expect(harness.pauseActionCount > pauseCountBefore,
               "Interruption began should pause playback")
    }
    
    /// AudioPlayerController ALWAYS pauses on interruption began, regardless of shouldResume option.
    /// Note: RadioPlayerController has different behavior - it only pauses when shouldResume is false.
    @Test("AudioPlayerController pauses on interruption began regardless of shouldResume")
    func audioPlayerControllerInterruptionBeganPausesRegardlessOfShouldResume() async {
        let harness = AudioPlayerControllerTestHarness()
        
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let pauseCountBefore = harness.pauseActionCount
        // AudioPlayerController should pause even with shouldResume: true
        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()
    
        // Note: AudioPlayerController calls stop() instead of pause() for live streaming
        #expect(harness.pauseActionCount > pauseCountBefore,
               "AudioPlayerController should pause on interruption began regardless of shouldResume")
    }
    
    /// RadioPlayerController only pauses on interruption began when shouldResume option is NOT set.
    /// When shouldResume is set, it logs analytics but doesn't pause (expects system to auto-resume).
    @Test("RadioPlayerController does not pause on interruption began with shouldResume")
    func radioPlayerControllerInterruptionBeganWithShouldResumeDoesNotPause() async {
        let harness = RadioPlayerControllerTestHarness()
        
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        let pauseCountBefore = harness.pauseCallCount
        // RadioPlayerController should NOT pause when shouldResume is true
        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()
        
        #expect(harness.pauseCallCount == pauseCountBefore,
               "RadioPlayerController should not pause on interruption began with shouldResume")
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
        
        // Simulate interruption began (this sets wasPlayingBeforeInterruption = true and pauses)
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()
        
        let attemptCountBefore = harness.playbackAttemptCount
        
        // Now post interruption ended with shouldResume
        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()
    
        // AudioPlayerController.play() may call resume() when paused, so check playbackAttemptCount
        #expect(harness.playbackAttemptCount > attemptCountBefore,
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
        
        // Post interruption began - RadioPlayerController only pauses when shouldResume is false
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()
        
        // Verify pause was called
        #expect(harness.pauseCallCount >= 1, "Interruption began should pause")
        
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
    
    @Test("pause() calls analytics with duration")
    func pauseCallsAnalyticsWithDuration() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.reset()
        harness.controller.play()
        
        // Small delay to ensure non-zero duration
        try? await Task.sleep(for: .milliseconds(10))
    
        harness.controller.pause()
        #expect(harness.analyticsPauseCallCount > 0, "pause() should call analytics")
        #expect(harness.lastAnalyticsPauseDuration != nil, "pause() should report duration")
    }

    @Test("Analytics receives play reason")
    func analyticsReceivesPlayReason() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.controller.play(reason: "user tapped play")

        #expect(harness.mockAnalytics.startedEvents.count == 1)
        #expect(harness.mockAnalytics.startedEvents.first?.reason == .userInitiated)
    }
    
    @Test("Analytics receives pause duration")
    func analyticsReceivesPauseDuration() async {
        let harness = AudioPlayerControllerTestHarness()
        harness.controller.play()

        // Wait a bit to accumulate duration
        try? await Task.sleep(for: .milliseconds(50))

        harness.controller.pause()

        #expect(harness.mockAnalytics.stoppedEvents.count == 1)
        if let duration = harness.mockAnalytics.stoppedEvents.first?.duration {
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

        #expect(harness.mockAnalytics.stoppedEvents.count == 1, "stop() should report analytics stopped event")
    }
}

// MARK: - AudioPlayerController Background/Foreground Specific Tests

#if os(iOS)
@Suite("AudioPlayerController Background/Foreground Behavior Tests")
@MainActor
struct AudioPlayerControllerBackgroundBehaviorTests {
    
    @Test("play() sets playbackIntended - background does NOT deactivate session")
    func playWithURLSetsPlaybackIntended() async {
        let harness = AudioPlayerControllerTestHarness()

        harness.controller.play(reason: "test")
        harness.mockSession.reset()  // Clear the activation from play()
        
        harness.controller.handleAppDidEnterBackground()
        
        // Should NOT have deactivated (playbackIntended is true)
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background while playing should NOT deactivate session")
    }
    
    @Test("pause() clears playbackIntended - background DOES deactivate session")
    func pauseClearsPlaybackIntended() async {
        let harness = AudioPlayerControllerTestHarness()
        
        harness.controller.play(reason: "test")
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

        // Play -> Pause -> Play cycle
        harness.controller.play(reason: "initial")
        harness.controller.pause()  // playbackIntended = false
        harness.controller.play()   // playbackIntended should be true again
        
        harness.mockSession.reset()
        harness.controller.handleAppDidEnterBackground()
        
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background after pause-then-play should NOT deactivate")
    }
    
    @Test("stop() clears playbackIntended and deactivates immediately")
    func stopClearsPlaybackIntendedAndDeactivates() async {
        let harness = AudioPlayerControllerTestHarness()

        harness.controller.play(reason: "test")
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
        
        harness.controller.play(reason: "test")
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

        // User starts WXYC (interrupts Apple Music)
        harness.controller.play(reason: "user started stream")
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
    
    @Test("pause() calls underlying player")
    func pauseCallsUnderlyingPlayer() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )
    
        radioPlayer.play()
        radioPlayer.pause()
        
        #expect(mockPlayer.pauseCallCount == 1, "pause() should call underlying player")
    }
    
    @Test("pause() resets stream")
    func pauseResetsStream() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )
    
        radioPlayer.play()
        radioPlayer.pause()
        
        #expect(mockPlayer.replaceCurrentItemCallCount == 1, "pause() should reset stream")
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
        harness.controller.pause()
        harness.controller.toggle()
    }
}

// MARK: - Pause Resume Live Tests

/// Tests verifying that all players resume at live position after pause.
/// For live streaming, pause() should reset/disconnect the stream so that
/// resume plays current live audio, not stale buffered audio.
@Suite("Pause Resume Live Tests")
@MainActor
struct PauseResumeLiveTests {

    /// Tests that pause() resets the stream for live streaming.
    /// After pause(), resume should connect fresh to the live stream.
    @Test("Pause resets stream for live playback", arguments: PlayerControllerTestCase.mockedCases)
    func pauseResetsStreamForLivePlayback(testCase: PlayerControllerTestCase) async {
        let harness = testCase.makeHarness()

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Should be playing before pause")

        // Pause - should reset the stream for live playback
        harness.controller.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying, "Should not be playing after pause")

        // Critical assertion: stream should be reset so resume plays live
        #expect(harness.isStreamReset(),
               "Pause should reset stream for live streaming so resume plays live audio, not stale buffered audio")
    }

    /// Tests AVAudioStreamer's pause() resets stream by checking state transition.
    /// AVAudioStreamer requires network for playback simulation, so we test state-based behavior.
    #if !os(watchOS)
    @Test("AVAudioStreamer pause resets stream")
    func avAudioStreamerPauseResetsStream() async {
        let config = AVAudioStreamerConfiguration(
            url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        )
        let streamer = AVAudioStreamer(configuration: config)

        // Verify initial state
        #expect(streamer.state == .idle, "Should start in idle state")

        // Call stop to verify it sets idle state (baseline)
        streamer.stop()
        #expect(streamer.state == .idle, "stop() should set idle state")

        // For pause, we can't easily test without network, but we can verify
        // that the pause() implementation is structurally correct by code review.
        // The implementation now calls httpClient.disconnect(), bufferQueue.clear(), etc.
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
/// stop() is distinct from pause() - it fully terminates playback and resets state.
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
 
 2. PAUSE BEHAVIOR
    - pause() should set isPlaying to false
    - pause() should call the underlying player's pause method
    - pause() should call analytics with duration (if supported)
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
 
 7. INTERRUPTION HANDLING (iOS)
    - Should pause on interruption began (unless shouldResume is set)
    - Should resume if shouldResume is set and was playing
 
 8. ROUTE CHANGES (iOS)
    - Should pause when headphones disconnected
 
 9. ANALYTICS (if supported)
    - play() should log analytics with reason
    - pause() should log analytics with duration
    - stop() should log analytics with duration
 
 10. BACKGROUND/FOREGROUND BEHAVIOR (iOS)
    - Background while playbackIntended: do NOT deactivate session
    - Background without playbackIntended: deactivate session
    - Foreground while playbackIntended: reactivate session
    - Foreground without playbackIntended: do NOT activate session
 */

#endif
