//
//  RadioPlayerControllerTests.swift
//  Playback
//
//  Tests for RadioPlayerController behavior.
//
//  Created by Jake Bromberg on 11/11/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

/*
 RadioPlayerControllerTests.swift

 Unit tests for RadioPlayerController-specific functionality.

 Note: Common behavior tests (play/stop/toggle, background/foreground, interruption
 handling, analytics, stall recovery) are now covered by parameterized tests in
 PlaybackTests/Behavior/ that test both RadioPlayerController and AudioPlayerController.

 This file contains only RadioPlayerController-specific tests:
 - State observation through RadioPlayer notifications
 - Error handling for audio session failures
 - Route change notification handling
 */

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
import MediaPlayer
import Core
@testable import RadioPlayerModule
@testable import PlaybackCore

// MARK: - Mock Audio Session

#if os(iOS) || os(tvOS)
final class MockAudioSession: AudioSessionProtocol {
    var setActiveCallCount = 0
    var lastActiveState: Bool?
    var outputLatency: TimeInterval = 0

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {}

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, policy: AVAudioSession.RouteSharingPolicy, options: AVAudioSession.CategoryOptions) throws {}

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        setActiveCallCount += 1
        lastActiveState = active
    }

    var currentRoute: AVAudioSessionRouteDescription {
        AVAudioSession.sharedInstance().currentRoute
    }
}
#endif

// MARK: - RadioPlayerController Test Factory

import Analytics
import AnalyticsTesting

extension RadioPlayerController {
    /// Creates a RadioPlayerController configured for testing with platform-appropriate mocks
    @MainActor
    static func makeForTesting(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(
            player: MockPlayer(),
            analytics: nil
        ),
        notificationCenter: NotificationCenter = NotificationCenter(),
        analytics: AnalyticsService = MockStructuredAnalytics(),
        backoffTimer: ExponentialBackoff = .default
    ) -> RadioPlayerController {
        #if os(iOS) || os(tvOS)
        RadioPlayerController(
            radioPlayer: radioPlayer,
            audioSession: MockAudioSession(),
            notificationCenter: notificationCenter,
            analytics: analytics,
            remoteCommandCenter: .shared(),
            backoffTimer: backoffTimer
        )
        #else
        RadioPlayerController(
            radioPlayer: radioPlayer,
            notificationCenter: notificationCenter,
            analytics: analytics,
            backoffTimer: backoffTimer
        )
        #endif
    }
}

// MARK: - RadioPlayerController Tests

@Suite("RadioPlayerController Tests")
@MainActor
struct RadioPlayerControllerTests {

    // MARK: - State Observation Tests

    @Test("Observes radio player state changes", .timeLimit(.minutes(1)))
    func observesRadioPlayerStateChanges() async throws {
        // Given
        let mockPlayer = MockPlayer()
        let notificationCenter = NotificationCenter()
        let radioPlayer = RadioPlayer(
            player: mockPlayer,
            analytics: nil,
            notificationCenter: notificationCenter
        )

        let observersReady = AsyncStream<Void>.makeStream()

        let controller = RadioPlayerController.makeForTesting(
            radioPlayer: radioPlayer,
            notificationCenter: notificationCenter
        )
        controller.onObserversReady = {
            observersReady.continuation.yield()
            observersReady.continuation.finish()
        }

        // Wait for observers to be ready
        for await _ in observersReady.stream { break }

        // Start listening to state stream BEFORE triggering state change
        // to avoid race condition
        let stateTask = Task {
            for await state in radioPlayer.stateStream {
                if state == .playing {
                    return true
                }
            }
            return false
        }

        // Give the task a moment to start listening
        try await Task.sleep(for: .milliseconds(50))

        // When - Start playing via radio player
        radioPlayer.play()

        // Simulate rate change notification on the mock player
        mockPlayer.rate = 1.0
        notificationCenter.post(
            name: AVPlayer.rateDidChangeNotification,
            object: mockPlayer,
            userInfo: ["rate": Float(1.0)]
        )

        // Wait for state change with timeout
        let result = await stateTask.value

        // Then - Controller should observe the change
        #expect(result == true, "State should have changed to playing")
        #expect(radioPlayer.isPlaying == true)
        #expect(controller.isPlaying == true)
    }

    // MARK: - Double-Count Regression Tests (#669)

    /// Constructs a controller with only the analytics sink (a mock, so the
    /// test can observe capture counts without touching the real PostHog
    /// singleton) and, on iOS/tvOS, the audio session substituted — the
    /// wrapped `radioPlayer` is left at its default, exactly as both the
    /// public convenience init `RadioPlayerController.shared` resolves to
    /// (production's watchOS path) and this designated init construct it.
    ///
    /// The pre-#669 defect's redundant emission targeted the live
    /// `StructuredPostHogAnalytics` singleton, not this test's injected
    /// `MockStructuredAnalytics` — so a `count == 1` assertion against the
    /// mock alone can't distinguish "the controller emitted once" from "the
    /// controller emitted once AND the default `radioPlayer` quietly emitted
    /// a second, unobserved 'play' to the real service." The
    /// `hasAnalyticsSink` assertion below closes that gap by inspecting the
    /// actual invariant #669 establishes on the wrapped player itself: it
    /// must carry no analytics sink at all, so it is structurally incapable
    /// of emitting regardless of what sink the controller uses. Together the
    /// two assertions pin "controller emits exactly one, wrapped player
    /// emits none" — which is what ends watchOS's unconditional double-count,
    /// since the watch app exclusively uses `RadioPlayerController`.
    @Test("The designated init's default RadioPlayer carries no analytics sink, so the controller alone emits exactly one play event (#669)")
    func defaultConstructionEmitsPlayExactlyOnce() throws {
        let mockAnalytics = MockStructuredAnalytics()

        #if os(iOS) || os(tvOS)
        let controller = RadioPlayerController(
            audioSession: MockAudioSession(),
            notificationCenter: NotificationCenter(),
            analytics: mockAnalytics,
            remoteCommandCenter: .shared()
        )
        #else
        let controller = RadioPlayerController(
            notificationCenter: NotificationCenter(),
            analytics: mockAnalytics
        )
        #endif

        let radioPlayer = try #require(controller.radioPlayer as? RadioPlayer, "The default wrapped player should be a RadioPlayer")
        #expect(radioPlayer.hasAnalyticsSink == false, "The default RadioPlayer must carry no analytics sink — the controller is the sole emitter")

        try controller.play(reason: .test)

        #expect(
            mockAnalytics.startedEvents.count == 1,
            "Expected exactly one play event, got \(mockAnalytics.startedEvents.count)"
        )

        controller.tearDown(reason: .test)
    }

    // MARK: - Error Handling Tests

    @Test("Handles audio session activation errors gracefully")
    func handlesAudioSessionErrors() async throws {
        // Given
        let mockPlayer = MockPlayer()
        let radioPlayer = RadioPlayer(
            player: mockPlayer,
            analytics: nil
        )

        let observersReady = AsyncStream<Void>.makeStream()

        let controller = RadioPlayerController.makeForTesting(
            radioPlayer: radioPlayer
        )
        controller.onObserversReady = {
            observersReady.continuation.yield()
            observersReady.continuation.finish()
        }

        // Wait for observers to be ready
        for await _ in observersReady.stream { break }

        // When - Attempt to play (may fail to activate session in test environment)
        // This should not crash
        try controller.play(reason: .errorHandlingTest)

        // Then - Should handle gracefully
        #expect(true) // No crash = success
    }

    // MARK: - Route Change Tests

    #if os(iOS) || os(tvOS)
    @Test("Handles route change notification")
    func handlesRouteChange() async {
        // Given
        let mockPlayer = MockPlayer()
        let radioPlayer = RadioPlayer(
            player: mockPlayer,
            analytics: nil
        )
        let notificationCenter = NotificationCenter()

        let observersReady = AsyncStream<Void>.makeStream()

        let controller = RadioPlayerController.makeForTesting(
            radioPlayer: radioPlayer,
            notificationCenter: notificationCenter
        )
        controller.onObserversReady = {
            observersReady.continuation.yield()
            observersReady.continuation.finish()
        }

        // Wait for observers to be ready
        for await _ in observersReady.stream { break }

        // When - This should not crash or throw
        notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)

        // Then - Should handle gracefully (just logs)
        #expect(true) // No crash = success
    }
    #endif
}
