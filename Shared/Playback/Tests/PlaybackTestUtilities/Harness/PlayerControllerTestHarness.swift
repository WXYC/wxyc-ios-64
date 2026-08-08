//
//  PlayerControllerTestHarness.swift
//  Playback
//
//  Shared test infrastructure for parameterized PlaybackController tests.
//  Provides a unified harness for testing all controller implementations.
//
//  Created by Jake Bromberg on 12/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import AVFoundation
import MediaPlayer
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import MP3StreamerModule
#endif
import Analytics
import AnalyticsTesting
import Core

// MARK: - PlaybackController Test Convenience Extensions

/// Convenience methods for testing - allows calling play()/toggle()/stop() without reason parameter
public extension PlaybackController {
    func play() {
        try? play(reason: .test)
    }

    func toggle() {
        try? toggle(reason: .test)
    }

    func stop() {
        stop(reason: .test)
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
    public let mockAnalytics: MockStructuredAnalytics
    /// Stands in for `UIApplication`'s background-task assertions.
    ///
    /// Injected only into `AudioPlayerController` — it is the only controller
    /// with a deferred handback to protect. It is still constructed for the
    /// `RadioPlayerController` harnesses so the field is non-optional, but
    /// nothing there writes to it, so asserting against it from a radio test
    /// would pass no matter what the code did.
    public let mockBackgroundTasks: MockBackgroundTaskAssertion

    // For controller-specific backoff access
    private let radioPlayerController: RadioPlayerController?
    private let audioPlayerController: AudioPlayerController?

    /// Tracks stop count at start of last play to detect stream reset
    private var stopCountAtLastPlay = 0

    // MARK: - Computed Properties

    public var playCallCount: Int { mockPlayer.playCallCount }
    public var stopCallCount: Int { mockPlayer.stopCallCount }
    public var sessionActivated: Bool { mockSession.lastActiveState == true }
    public var sessionDeactivated: Bool { mockSession.lastActiveState == false }

    /// The concrete `AudioPlayerController`, when this harness wraps one. Lets a
    /// test read `debugState` for async state the `PlaybackController`
    /// protocol doesn't surface — notably whether a deferred audio-session
    /// deactivation has finished.
    public var audioController: AudioPlayerController? { audioPlayerController }

    /// Whether a deferred audio-session handback has run and been accounted for.
    ///
    /// `sessionDeactivationInFlight` is set synchronously by `stop()` and
    /// cleared only once the deactivation's continuation has recorded its
    /// outcome, so this is an edge a test can wait on instead of guessing a
    /// duration. Reads the typed `debugState` rather than substring-matching
    /// `debugStateSnapshot`, so renaming the field breaks this at compile time
    /// instead of leaving every caller silently waiting out its full timeout
    /// and then passing anyway.
    ///
    /// For the `RadioPlayerController` arm this is constantly `true` — the
    /// honest answer, not a stub: that controller hands the session back
    /// synchronously on the caller's turn (see #778), so there is never an
    /// unsettled handback to wait on. A settlement-gated assertion is a no-op
    /// there, not a hidden vacuous pass.
    public var sessionDeactivationSettled: Bool {
        audioPlayerController.map { !$0.debugState.sessionDeactivationInFlight } ?? true
    }
    
    public var analyticsPlayCallCount: Int { 
        mockAnalytics.events.filter { $0 is PlaybackStartedEvent }.count 
    }
    
    public var analyticsStopCallCount: Int { 
        mockAnalytics.events.filter { $0 is PlaybackStoppedEvent }.count 
    }
    
    public var lastAnalyticsPlayReason: String? {
        (mockAnalytics.events.reversed().first(where: { $0 is PlaybackStartedEvent }) as? PlaybackStartedEvent)?.reason
    }

    public var lastAnalyticsStopDuration: TimeInterval? {
        (mockAnalytics.events.reversed().first(where: { $0 is PlaybackStoppedEvent }) as? PlaybackStoppedEvent)?.duration
    }

    public var supportsStallSimulation: Bool { true }

    // MARK: - Private Initializer

    private init(
        controller: any PlaybackController,
        notificationCenter: NotificationCenter,
        mockPlayer: MockAudioPlayer,
        mockSession: MockAudioSession,
        mockCommandCenter: MockRemoteCommandCenter?,
        mockAnalytics: MockStructuredAnalytics,
        mockBackgroundTasks: MockBackgroundTaskAssertion,
        radioPlayerController: RadioPlayerController? = nil,
        audioPlayerController: AudioPlayerController? = nil
    ) {
        self.controller = controller
        self.notificationCenter = notificationCenter
        self.mockPlayer = mockPlayer
        self.mockSession = mockSession
        self.mockCommandCenter = mockCommandCenter
        self.mockAnalytics = mockAnalytics
        self.mockBackgroundTasks = mockBackgroundTasks
        self.radioPlayerController = radioPlayerController
        self.audioPlayerController = audioPlayerController
    }

    // MARK: - Factory Method

    /// Creates a test harness for the specified controller type
    /// - Parameters:
    ///   - testCase: The type of controller to create
    ///   - backoffTimer: Optional custom backoff timer for testing exhaustion scenarios
    ///   - heartbeatInterval: Cadence for the `playback_heartbeat` timer (#666).
    ///     Defaults to the 60s production value; tests exercising the cadence
    ///     itself inject a short interval so several ticks happen quickly.
    ///   - sessionActivationRetryDelay: Spacing of the bounded `'!int'`
    ///     activation retries (#514). Defaults to the 250ms production value;
    ///     tests that must outlast the whole budget inject a short delay.
    ///     Applies to the `.audioPlayerController` case only.
    public static func make(
        for testCase: PlayerControllerTestCase,
        backoffTimer: ExponentialBackoff = .default,
        heartbeatInterval: Duration = .seconds(60),
        sessionActivationRetryDelay: Duration = .milliseconds(250)
    ) -> PlayerControllerTestHarness {
        let streamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let mockPlayer = MockAudioPlayer(url: streamURL)
        let mockAnalytics = MockStructuredAnalytics()
        let mockBackgroundTasks = MockBackgroundTaskAssertion()
        let notificationCenter = NotificationCenter()

        switch testCase {
        #if os(iOS) || os(tvOS)
        case .audioPlayerController:
            let mockSession = MockAudioSession()
            let mockCommandCenter = MockRemoteCommandCenter()

            let audioController = AudioPlayerController(
                player: mockPlayer,
                audioSession: mockSession,
                remoteCommandCenter: mockCommandCenter,
                notificationCenter: notificationCenter,
                analytics: mockAnalytics,
                backoffTimer: backoffTimer,
                heartbeatInterval: heartbeatInterval,
                sessionActivationRetryDelay: sessionActivationRetryDelay,
                backgroundTasks: mockBackgroundTasks
            )

            return PlayerControllerTestHarness(
                controller: audioController,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockSession: mockSession,
                mockCommandCenter: mockCommandCenter,
                mockAnalytics: mockAnalytics,
                mockBackgroundTasks: mockBackgroundTasks,
                audioPlayerController: audioController
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
                remoteCommandCenter: .shared(),
                backoffTimer: backoffTimer,
                heartbeatInterval: heartbeatInterval
            )

            return PlayerControllerTestHarness(
                controller: radioController,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockSession: mockSession,
                mockCommandCenter: nil,
                mockAnalytics: mockAnalytics,
                mockBackgroundTasks: mockBackgroundTasks,
                radioPlayerController: radioController
            )
            #else
            let mockSession = MockAudioSession()
            let radioController = RadioPlayerController(
                radioPlayer: mockPlayer,
                notificationCenter: notificationCenter,
                analytics: mockAnalytics,
                backoffTimer: backoffTimer,
                heartbeatInterval: heartbeatInterval
            )

            return PlayerControllerTestHarness(
                controller: radioController,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockSession: mockSession,
                mockCommandCenter: nil,
                mockAnalytics: mockAnalytics,
                mockBackgroundTasks: mockBackgroundTasks,
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

    /// Lets any pending MainActor-isolated work drain — the controller's
    /// `for await state in player.stateStream` observer task, queued
    /// `Task { @MainActor … }` blocks, and so on.
    ///
    /// Implementation: yield repeatedly until the controller's mirrored
    /// `playerState` has converged with the mock player's state, then yield a
    /// few more times to drain anything else still queued. Capped by a
    /// wall-clock deadline (using `ContinuousClock`, not `Task.sleep`) so a
    /// stuck observer can't hang the test indefinitely.
    public func waitForAsync() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))

        // Phase 1: drain until the controller's stored state mirrors the mock.
        // The state observer is `Task { for await s in player.stateStream { … } }`
        // hopping back to MainActor on each yielded value — that round-trip can
        // need several `Task.yield()` to drain. Loop until convergence (or the
        // deadline expires as a safety net).
        while ContinuousClock.now < deadline,
              !isControllerStateConverged() {
            await Task.yield()
        }

        // Phase 2: a fixed burst of yields to flush any remaining queued work
        // (analytics, audio-session activation, etc.) that doesn't surface
        // through `playerState`.
        for _ in 0..<16 {
            await Task.yield()
        }
    }

    /// Whether the controller's mirrored player-state matches the mock player.
    /// Used by `waitForAsync` to block until the state observer has caught up.
    /// Returns `true` for controllers that update state synchronously, since
    /// they have nothing to drain.
    private func isControllerStateConverged() -> Bool {
        if let audioPlayerController {
            return audioPlayerController.isPlaying == mockPlayer.isPlaying
        }
        // RadioPlayerController mirrors its mock player synchronously via
        // `MainActorNotificationMessage`, so it's always converged by the
        // time control returns to the test.
        return true
    }

    /// Polls until condition is met or timeout expires. Delegates to the
    /// package-wide `pollUntil` so every suite shares one set of timeout
    /// mechanics.
    public func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = stallTolerantTimeout) async {
        await pollUntil(condition, timeout: timeout)
    }

    /// Resets all tracked state. Settles the deferred audio-session handback
    /// the `stop()` here schedules before zeroing the mocks — otherwise the
    /// handback lands in the freshly-reset mock after this returns, and a test
    /// that resets mid-flight sees a phantom `setActive(false, …)` in its
    /// counters.
    public func reset() async {
        controller.stop(reason: .test)
        await waitUntil({ self.sessionDeactivationSettled })
        mockPlayer.reset()
        mockSession.reset()
        mockCommandCenter?.reset()
        mockAnalytics.reset()
        mockBackgroundTasks.reset()
        stopCountAtLastPlay = 0
    }

    /// Returns true if stop() reset the stream for live playback
    public func isStreamReset() -> Bool {
        mockPlayer.stopCallCount > stopCountAtLastPlay
    }

    /// Simulates a playback stall
    public func simulateStall() {
        // Disable auto-update so subsequent play() calls don't auto-recover
        // This simulates a persistent network issue where reconnection attempts fail
        mockPlayer.shouldAutoUpdateState = false
        mockPlayer.simulateStall()
        // For RadioPlayerController, post the stall notification
        if radioPlayerController != nil {
            notificationCenter.post(name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
        }
    }

    /// Returns the number of backoff attempts, if applicable
    public func getBackoffAttempts() -> UInt? {
        if let radioPlayerController {
            return radioPlayerController.backoffTimer.numberOfAttempts
        }
        if let audioPlayerController {
            return audioPlayerController.backoffTimer.numberOfAttempts
        }
        return nil
    }

    /// Simulates an error event from the player
    public func simulateError(_ error: Error) {
        mockPlayer.simulateError(error)
    }

    /// Returns all captured stream error events
    public var streamErrorEvents: [StreamErrorEvent] {
        mockAnalytics.events.compactMap { $0 as? StreamErrorEvent }
    }

    /// Returns all captured `playback_heartbeat` events (#666), in emission order.
    public var heartbeatEvents: [PlaybackHeartbeatEvent] {
        mockAnalytics.events.compactMap { $0 as? PlaybackHeartbeatEvent }
    }

    #if os(iOS)
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

    /// Posts a route change notification with the specified reason
    public func postRouteChange(reason: AVAudioSession.RouteChangeReason) {
        let userInfo: [AnyHashable: Any] = [
            AVAudioSessionRouteChangeReasonKey: NSNumber(value: reason.rawValue)
        ]
        notificationCenter.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    /// Simulates the audio engine stopping unexpectedly (as happens on some route changes)
    /// This simulates what happens when AVAudioEngine stops due to a route change
    public func simulateEngineStoppedDueToRouteChange() {
        // The mock player stops playing but doesn't go through the normal stop() path
        // This simulates the engine stopping without the controller knowing
        mockPlayer.isPlaying = false
        mockPlayer.state = .idle
    }
    #endif
}
