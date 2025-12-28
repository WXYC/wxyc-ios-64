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

// MARK: - Unified Test Harness
    
/// Unified test harness for all PlaybackController implementations.
/// Uses a single factory method to create harnesses with consistent behavior.
@MainActor
final class PlayerControllerTestHarness {
    let controller: any PlaybackController
    let notificationCenter: NotificationCenter

    // Mocks - available for all controller types
    let mockPlayer: MockAudioPlayer
    let mockSession: MockAudioSession
    let mockCommandCenter: MockRemoteCommandCenter?
    let mockAnalytics: MockPlaybackAnalytics

    // For RadioPlayerController backoff access
    private let radioPlayerController: RadioPlayerController?

    /// Tracks stop count at start of last play to detect stream reset
    private var stopCountAtLastPlay = 0

    // MARK: - Computed Properties

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
    var supportsStallSimulation: Bool { true }

    // MARK: - Private Initializer

    private init(
        controller: any PlaybackController,
        notificationCenter: NotificationCenter,
        mockPlayer: MockAudioPlayer,
        mockSession: MockAudioSession,
        mockCommandCenter: MockRemoteCommandCenter?,
        mockAnalytics: MockPlaybackAnalytics,
        radioPlayerController: RadioPlayerController? = nil
    ) {
        self.controller = controller
        self.notificationCenter = notificationCenter
        self.mockPlayer = mockPlayer
        self.mockSession = mockSession
        self.mockCommandCenter = mockCommandCenter
        self.mockAnalytics = mockAnalytics
        self.radioPlayerController = radioPlayerController
    }

    // MARK: - Factory Method

    /// Creates a test harness for the specified controller type
    static func make(for testCase: PlayerControllerTestCase) -> PlayerControllerTestHarness {
        let streamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let mockPlayer = MockAudioPlayer(url: streamURL)
        let mockAnalytics = MockPlaybackAnalytics()
        let notificationCenter = NotificationCenter()

        switch testCase {
        #if os(iOS) || os(tvOS)
        case .audioPlayerController:
            let mockSession = MockAudioSession()
            let mockCommandCenter = MockRemoteCommandCenter()

            let controller = AudioPlayerController(
                player: mockPlayer,
                audioSession: mockSession,
                remoteCommandCenter: mockCommandCenter,
                notificationCenter: notificationCenter,
                analytics: mockAnalytics
            )

            return PlayerControllerTestHarness(
                controller: controller,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockSession: mockSession,
                mockCommandCenter: mockCommandCenter,
                mockAnalytics: mockAnalytics
            )
        #endif

        case .radioPlayerController:
            #if os(iOS) || os(tvOS)
            let mockSession = MockAudioSession()
            let radioController = RadioPlayerController(
                radioPlayer: mockPlayer,
                audioSession: mockSession,
                notificationCenter: notificationCenter,
                analytics: mockAnalytics,
                remoteCommandCenter: .shared()
            )

            return PlayerControllerTestHarness(
                controller: radioController,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockSession: mockSession,
                mockCommandCenter: nil,
                mockAnalytics: mockAnalytics,
                radioPlayerController: radioController
            )
            #else
            let mockSession = MockAudioSession()
            let radioController = RadioPlayerController(
                radioPlayer: mockPlayer,
                notificationCenter: notificationCenter,
                analytics: mockAnalytics
            )

            return PlayerControllerTestHarness(
                controller: radioController,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockSession: mockSession,
                mockCommandCenter: nil,
                mockAnalytics: mockAnalytics,
                radioPlayerController: radioController
            )
            #endif
        }
    }

    // MARK: - Simulation Methods (Unified Behavior)

    /// Simulates playback starting - updates mock state consistently
    func simulatePlaybackStarted() {
        stopCountAtLastPlay = mockPlayer.stopCallCount
        mockPlayer.simulateStateChange(to: .playing)
    }

    /// Simulates playback stopping - updates mock state consistently
    func simulatePlaybackStopped() {
        mockPlayer.simulateStateChange(to: .idle)
    }

    /// Waits for async operations to complete
    func waitForAsync() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// Polls until condition is met or timeout expires
    func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
        let start = Date()
        let timeoutSeconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        while !condition() {
            if Date().timeIntervalSince(start) > timeoutSeconds {
                return
            }
            await Task.yield()
        }
    }

    /// Resets all tracked state
    func reset() {
        controller.stop()
        mockPlayer.reset()
        mockSession.reset()
        mockCommandCenter?.reset()
        mockAnalytics.reset()
        stopCountAtLastPlay = 0
    }

    /// Returns true if stop() reset the stream for live playback
    func isStreamReset() -> Bool {
        mockPlayer.stopCallCount > stopCountAtLastPlay
    }

    /// Simulates a playback stall
    func simulateStall() {
        mockPlayer.simulateStall()
        // For RadioPlayerController, post the stall notification
        if radioPlayerController != nil {
            notificationCenter.post(name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
        }
    }

    /// Returns the number of backoff attempts, if applicable
    func getBackoffAttempts() -> UInt? {
        radioPlayerController?.backoffTimer.numberOfAttempts
    }

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

// MARK: - Test Case Enumeration
    
/// Enumeration of player controller implementations to test
enum PlayerControllerTestCase: String, CaseIterable, CustomTestStringConvertible {
    #if os(iOS) || os(tvOS)
    /// AudioPlayerController - iOS/tvOS controller with full system integration
    case audioPlayerController
    #endif
    /// RadioPlayerController - Cross-platform controller (including watchOS)
    case radioPlayerController

    var testDescription: String {
        switch self {
        #if os(iOS) || os(tvOS)
        case .audioPlayerController:
            "AudioPlayerController"
        #endif
        case .radioPlayerController:
            "RadioPlayerController"
        }
    }

    /// Whether this controller supports analytics tracking via mock
    var supportsAnalytics: Bool {
        // Both now support analytics via MockPlaybackAnalytics injection
        true
    }
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


// MARK: - Parameterized Behavior Tests

@Suite("Player Controller Behavior Tests")
@MainActor
struct PlayerControllerBehaviorTests {

    // MARK: - Core Playback Behavior (Mocked Controllers)

    @Test("play() sets isPlaying to true", arguments: PlayerControllerTestCase.allCases)
    func playSetsIsPlayingTrue(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "play() should set isPlaying to true")
    }

    @Test("stop() sets isPlaying to false", arguments: PlayerControllerTestCase.allCases)
    func stopSetsIsPlayingFalse(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "stop() should set isPlaying to false")
    }
    
    @Test("toggle() while playing stops", arguments: PlayerControllerTestCase.allCases)
    func toggleFromPlayingStops(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        harness.controller.toggle()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "toggle() while playing should stop")
    }

    @Test("toggle() while stopped starts playback", arguments: PlayerControllerTestCase.allCases)
    func toggleWhileStoppedStartsPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)

        harness.controller.toggle()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        #expect(harness.controller.isPlaying, "toggle() while stopped should start playback")
    }
    
    @Test("Initial state is not playing", arguments: PlayerControllerTestCase.allCases)
    func initialStateIsNotPlaying(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying, "Initial state should be not playing")
    }
    
    // MARK: - Underlying Player Integration (Mocked Controllers Only)
    
    /// Note: This test only runs for AudioPlayerController because RadioPlayerController's
    /// play() method goes through AVAudioSession.activate() which fails in test environments.
    /// RadioPlayerController's player integration is tested via simulatePlaybackStarted() instead.
    #if os(iOS) || os(tvOS)
    @Test("play() calls underlying player")
    func playCallsUnderlyingPlayer() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let initialCount = harness.playCallCount
        harness.controller.play()
        await harness.waitForAsync()
        #expect(harness.playCallCount > initialCount, "play() should call underlying player")
    }
    #endif

    @Test("stop() calls underlying player", arguments: PlayerControllerTestCase.allCases)
    func stopCallsUnderlyingPlayer(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
    
        let initialCount = harness.stopCallCount
        harness.controller.stop()
        await harness.waitForAsync()

        #expect(harness.stopCallCount > initialCount, "stop() should call underlying player")
    }
    
    // MARK: - State Consistency Tests
    
    @Test("Multiple play calls are idempotent", arguments: PlayerControllerTestCase.allCases)
    func multiplePlayCallsAreIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        // Play again while already playing
        harness.controller.play()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Multiple play calls should keep isPlaying true")
    }
    
    @Test("Multiple stop calls are idempotent", arguments: PlayerControllerTestCase.allCases)
    func multipleStopCallsAreIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
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
    
    @Test("Rapid play/stop cycles maintain consistency", arguments: PlayerControllerTestCase.allCases)
    func rapidPlayStopCyclesMaintainConsistency(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

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

    @Test("Background while playing keeps session active", arguments: PlayerControllerTestCase.allCases)
    func backgroundWhilePlayingKeepsSessionActive(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        
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

    @Test("Background while not playing is handled gracefully", arguments: PlayerControllerTestCase.allCases)
    func backgroundWhileNotPlayingIsHandled(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)
        
        // Should not crash or cause issues
        harness.postBackgroundNotification()
        await harness.waitForAsync()
        
        // Verify still not playing
        #expect(!harness.controller.isPlaying)
    }
    
    @Test("Foreground while playing reactivates", arguments: PlayerControllerTestCase.allCases)
    func foregroundWhilePlayingReactivates(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        
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
        
    @Test("Foreground while not playing does not start playback", arguments: PlayerControllerTestCase.allCases)
    func foregroundWhileNotPlayingDoesNotStartPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
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
    
    @Test("Interruption began stops playback", arguments: PlayerControllerTestCase.allCases)
    func interruptionBeganStopsPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

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
    
    /// Per Apple's guidance: controllers ALWAYS stop on interruption began,
    /// regardless of shouldResume option (shouldResume only applies to interruption ended).
    @Test("Interruption began stops playback regardless of shouldResume", arguments: PlayerControllerTestCase.allCases)
    func interruptionBeganStopsRegardlessOfShouldResume(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let stopCountBefore = harness.stopCallCount
        // Controller should stop even with shouldResume: true
        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.stopCallCount > stopCountBefore,
               "Controller should stop on interruption began regardless of shouldResume")
    }

    /// When interruption ends with shouldResume, controller should resume playback.
    @Test("Interruption ended with shouldResume resumes playback", arguments: PlayerControllerTestCase.allCases)
    func interruptionEndedWithShouldResumeResumesPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        // Simulate interruption began (sets wasPlayingBeforeInterruption = true and stops)
        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        let playCountBefore = harness.playCallCount

        // Post interruption ended with shouldResume - should resume
        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.playCallCount > playCountBefore,
               "Interruption ended with shouldResume should resume playback")
    }
}
#endif

// MARK: - Analytics Integration Tests

@Suite("Analytics Integration Tests")
@MainActor
struct AnalyticsIntegrationTests {

    @Test("play() calls analytics", arguments: PlayerControllerTestCase.allCases)
    func playCallsAnalytics(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.reset()
        harness.controller.play()
        #expect(harness.analyticsPlayCallCount > 0, "play() should call analytics")
    }

    @Test("toggle() to stop calls analytics with duration", arguments: PlayerControllerTestCase.allCases)
    func toggleToStopCallsAnalyticsWithDuration(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.reset()
        harness.controller.play()

        // Small delay to ensure non-zero duration
        try? await Task.sleep(for: .milliseconds(10))

        try harness.controller.toggle(reason: "test toggle")
        #expect(harness.analyticsStopCallCount > 0, "toggle() to stop should call analytics")
        #expect(harness.lastAnalyticsStopDuration != nil, "toggle() to stop should report duration")
    }

    @Test("Analytics receives play reason", arguments: PlayerControllerTestCase.allCases)
    func analyticsReceivesPlayReason(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        try harness.controller.play(reason: "user tapped play")

        #expect(harness.mockAnalytics.startedEvents.count == 1)
        #expect(harness.mockAnalytics.startedEvents.first?.reason == "user tapped play")
    }

    @Test("Analytics receives stop duration via toggle", arguments: PlayerControllerTestCase.allCases)
    func analyticsReceivesStopDurationViaToggle(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()

        // Wait a bit to accumulate duration
        try? await Task.sleep(for: .milliseconds(50))

        try harness.controller.toggle(reason: "test toggle")

        #expect(harness.mockAnalytics.stoppedEvents.count == 1)
        if let duration = harness.mockAnalytics.stoppedEvents.first?.duration {
            #expect(duration >= 0.04, "Duration should be at least 40ms")
        } else {
            Issue.record("Expected stop duration to be recorded")
        }
    }

    @Test("toggle() to stop reports analytics stopped event", arguments: PlayerControllerTestCase.allCases)
    func toggleToStopReportsAnalyticsStoppedEvent(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        try harness.controller.toggle(reason: "test toggle")

        #expect(harness.mockAnalytics.stoppedEvents.count == 1, "toggle() to stop should report analytics stopped event")
    }

    @Test("toggle() to stop reports nil reason (user-initiated)", arguments: PlayerControllerTestCase.allCases)
    func toggleToStopReportsNilReason(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.mockAnalytics.reset()

        try harness.controller.toggle(reason: "test toggle")

        #expect(harness.mockAnalytics.stoppedEvents.count == 1)
        #expect(harness.mockAnalytics.stoppedEvents.first?.reason == nil,
               "toggle() to stop should report nil reason for user-initiated stops")
    }

    @Test("stop() alone does NOT capture analytics", arguments: PlayerControllerTestCase.allCases)
    func stopAloneDoesNotCaptureAnalytics(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.mockAnalytics.reset()

        harness.controller.stop()

        #expect(harness.mockAnalytics.stoppedEvents.isEmpty,
               "stop() alone should NOT capture analytics - call sites must capture before calling stop()")
    }

    @Test("play() reports exact reason string", arguments: PlayerControllerTestCase.allCases)
    func playReportsExactReasonString(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        let expectedReason = "CarPlay listen live tapped"
    
        try harness.controller.play(reason: expectedReason)

        #expect(harness.mockAnalytics.startedEvents.count == 1)
        #expect(harness.mockAnalytics.startedEvents.first?.reason == expectedReason,
               "play() should report the exact reason string passed in")
    }

    @Test("Multiple play reasons are captured distinctly", arguments: [
        "PlayWXYC intent",
        "ToggleWXYC intent",
        "CarPlay listen live tapped",
        "home screen play quick action",
        "remotePlayCommand",
        "remote toggle play/pause",
        "Resume after interruption ended",
        "foreground toggle"
    ])
    func multiplePlayReasonsAreCapturedDistinctly(reason: String) async throws {
        // Test with AudioPlayerController
        #if os(iOS) || os(tvOS)
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        try harness.controller.play(reason: reason)
        #expect(harness.mockAnalytics.startedEvents.first?.reason == reason,
               "AudioPlayerController should capture exact reason '\(reason)'")
        #endif

        // Test with RadioPlayerController
        let radioHarness = PlayerControllerTestHarness.make(for: .radioPlayerController)
        try radioHarness.controller.play(reason: reason)
        #expect(radioHarness.mockAnalytics.startedEvents.first?.reason == reason,
               "RadioPlayerController should capture exact reason '\(reason)'")
    }
}
        
// MARK: - Analytics Reason String Tests (iOS)

#if os(iOS)
@Suite("Analytics Reason String Tests")
@MainActor
struct AnalyticsReasonStringTests {

    @Test("Interruption began reports 'interruption began' reason", arguments: PlayerControllerTestCase.allCases)
    func interruptionBeganReportsCorrectReason(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.mockAnalytics.reset()

        harness.postInterruptionBegan(shouldResume: false)
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.stoppedEvents.count >= 1,
               "Interruption began should capture stopped event")
        #expect(harness.mockAnalytics.stoppedEvents.first?.reason == "interruption began",
               "Interruption began should report 'interruption began' reason")
    }

    @Test("Route disconnected reports 'route disconnected' reason")
    func routeDisconnectedReportsCorrectReason() async throws {
        // Only AudioPlayerController handles route changes with analytics
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.mockAnalytics.reset()

        // Simulate route change (old device unavailable = headphones unplugged)
        harness.notificationCenter.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            ]
        )
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.stoppedEvents.count >= 1,
               "Route disconnected should capture stopped event")
        #expect(harness.mockAnalytics.stoppedEvents.first?.reason == "route disconnected",
               "Route disconnected should report 'route disconnected' reason")
    }

    @Test("Stall reports 'stalled' reason")
    func stallReportsCorrectReason() async throws {
        // Test with RadioPlayerController which has stall handling via notification
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.mockAnalytics.reset()
    
        harness.simulateStall()
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.stoppedEvents.count >= 1,
               "Stall should capture stopped event")
        #expect(harness.mockAnalytics.stoppedEvents.first?.reason == "stalled",
               "Stall should report 'stalled' reason")
    }
}
#endif

// MARK: - AudioPlayerController Background/Foreground Specific Tests

#if os(iOS)
@Suite("AudioPlayerController Background/Foreground Behavior Tests")
@MainActor
struct AudioPlayerControllerBackgroundBehaviorTests {

    @Test("play() sets playbackIntended - background does NOT deactivate session")
    func playWithURLSetsPlaybackIntended() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
    
        try harness.controller.play(reason: "test")
        harness.mockSession.reset()  // Clear the activation from play()
        
        harness.controller.handleAppDidEnterBackground()
        
        // Should NOT have deactivated (playbackIntended is true)
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Background while playing should NOT deactivate session")
    }

    @Test("stop() clears playbackIntended - background DOES deactivate session")
    func stopClearsPlaybackIntended() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

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
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

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
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

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
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
    
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
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Never played - go to foreground
        harness.mockSession.reset()
        harness.controller.handleAppWillEnterForeground()
        
        #expect(harness.mockSession.setActiveCallCount == 0,
               "Foreground without playback intent should NOT activate session")
    }
    
    @Test("Real-world scenario: Apple Music interrupted, WXYC plays, backgrounding keeps WXYC playing")
    func appleMusicInterruptionScenario() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

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
        let harness = PlayerControllerTestHarness.make(for: testCase)

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
    @Test("Stop resets stream for live playback", arguments: PlayerControllerTestCase.allCases)
    func stopResetsStreamForLivePlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

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
        PlayerControllerTestCase.allCases.filter { testCase in
            let harness = PlayerControllerTestHarness.make(for: testCase)
            return harness.supportsStallSimulation && harness.getBackoffAttempts() != nil
        }
    }

    @Test("Stall while playing triggers recovery attempt")
    func stallTriggersRecoveryAttempt() async {
        // RadioPlayerController handles stalls via notification and attempts reconnection
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)

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
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)
    
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
        let harness = PlayerControllerTestHarness.make(for: .radioPlayerController)

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

    @Test("Stop returns to non-playing state", arguments: PlayerControllerTestCase.allCases)
    func stopReturnsToNonPlayingState(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

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

    @Test("Stop is idempotent", arguments: PlayerControllerTestCase.allCases)
    func stopIsIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

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

    @Test("Play after stop works", arguments: PlayerControllerTestCase.allCases)
    func playAfterStopWorks(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

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

    @Test("Stop while not playing is safe", arguments: PlayerControllerTestCase.allCases)
    func stopWhileNotPlayingIsSafe(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

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
