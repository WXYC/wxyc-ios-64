//
//  PlayerControllerTestHarness.swift
//  PlaybackTestUtilities
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
@testable import MP3StreamerModule
#endif

// MARK: - PlaybackController Test Convenience Extensions

/// Convenience methods for testing - allows calling play()/toggle() without reason parameter
public extension PlaybackController {
    func play() {
        try? play(reason: "test")
    }

    func toggle() {
        try? toggle(reason: "test")
    }
}

// MARK: - Test Case Enumeration

/// Enumeration of player controller implementations to test
public enum PlayerControllerTestCase: String, CaseIterable, CustomTestStringConvertible, Sendable {
    #if os(iOS) || os(tvOS)
    /// AudioPlayerController - iOS/tvOS controller with full system integration
    case audioPlayerController
    #endif
    /// RadioPlayerController - Cross-platform controller (including watchOS)
    case radioPlayerController

    public var testDescription: String {
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
    public var supportsAnalytics: Bool {
        // Both now support analytics via MockPlaybackAnalytics injection
        true
    }
}

// MARK: - Unified Test Harness

/// Unified test harness for all PlaybackController implementations.
/// Uses a single factory method to create harnesses with consistent behavior.
@MainActor
public final class PlayerControllerTestHarness {
    public let controller: any PlaybackController
    public let notificationCenter: NotificationCenter

    // Mocks - available for all controller types
    public let mockPlayer: MockAudioPlayer
    public let mockSession: MockAudioSession
    public let mockCommandCenter: MockRemoteCommandCenter?
    public let mockAnalytics: MockPlaybackAnalytics

    // For RadioPlayerController backoff access
    private let radioPlayerController: RadioPlayerController?

    /// Tracks stop count at start of last play to detect stream reset
    private var stopCountAtLastPlay = 0

    // MARK: - Computed Properties

    public var playCallCount: Int { mockPlayer.playCallCount }
    public var stopCallCount: Int { mockPlayer.stopCallCount }
    public var sessionActivated: Bool { mockSession.lastActiveState == true }
    public var sessionDeactivated: Bool { mockSession.lastActiveState == false }
    public var analyticsPlayCallCount: Int { mockAnalytics.startedEvents.count }
    public var analyticsStopCallCount: Int { mockAnalytics.stoppedEvents.count }
    public var lastAnalyticsPlayReason: String? {
        mockAnalytics.startedEvents.last.map { String(describing: $0.reason) }
    }
    public var lastAnalyticsStopDuration: TimeInterval? {
        mockAnalytics.stoppedEvents.last?.duration
    }
    public var supportsStallSimulation: Bool { true }

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
    public static func make(for testCase: PlayerControllerTestCase) -> PlayerControllerTestHarness {
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
    public func simulatePlaybackStarted() {
        stopCountAtLastPlay = mockPlayer.stopCallCount
        mockPlayer.simulateStateChange(to: .playing)
    }

    /// Simulates playback stopping - updates mock state consistently
    public func simulatePlaybackStopped() {
        mockPlayer.simulateStateChange(to: .idle)
    }

    /// Waits for async operations to complete
    public func waitForAsync() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// Polls until condition is met or timeout expires
    public func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
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
    public func reset() {
        controller.stop()
        mockPlayer.reset()
        mockSession.reset()
        mockCommandCenter?.reset()
        mockAnalytics.reset()
        stopCountAtLastPlay = 0
    }

    /// Returns true if stop() reset the stream for live playback
    public func isStreamReset() -> Bool {
        mockPlayer.stopCallCount > stopCountAtLastPlay
    }

    /// Simulates a playback stall
    public func simulateStall() {
        mockPlayer.simulateStall()
        // For RadioPlayerController, post the stall notification
        if radioPlayerController != nil {
            notificationCenter.post(name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
        }
    }

    /// Returns the number of backoff attempts, if applicable
    public func getBackoffAttempts() -> UInt? {
        radioPlayerController?.backoffTimer.numberOfAttempts
    }

    #if os(iOS)
    public func postBackgroundNotification() {
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    public func postForegroundNotification() {
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    public func postInterruptionBegan(shouldResume: Bool) {
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

    public func postInterruptionEnded(shouldResume: Bool) {
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

