//
//  PlayerControllerTestHarness.swift
//  PlaybackTests
//
//  Shared test infrastructure for parameterized PlaybackController tests.
//  Provides a unified harness for testing all controller implementations.
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
