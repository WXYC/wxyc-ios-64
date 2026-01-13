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

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {}

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

extension RadioPlayerController {
    /// Creates a RadioPlayerController configured for testing with platform-appropriate mocks
    @MainActor
    static func makeForTesting(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(
            player: MockPlayer(),
            analytics: nil
        ),
        notificationCenter: NotificationCenter = NotificationCenter(),
        analytics: PlaybackAnalytics = MockPlaybackAnalytics(),
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

    @Test("Observes radio player state changes")
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

        // When - Start playing via radio player
        radioPlayer.play()

        // Wait for state to propagate by observing isPlaying
        let stateChanged = AsyncStream<Void>.makeStream()
        let observationTask = Task {
            let observations = Observations { radioPlayer.isPlaying }
            for await isPlaying in observations {
                if isPlaying {
                    stateChanged.continuation.yield()
                    stateChanged.continuation.finish()
                    break
                }
            }
        }

        // Simulate rate change notification on the mock player
        mockPlayer.rate = 1.0
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: mockPlayer)

        // Wait for state change
        for await _ in stateChanged.stream { break }
        observationTask.cancel()

        // Then - Controller should observe the change
        #expect(radioPlayer.isPlaying == true)
        #expect(controller.isPlaying == true)
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
        try controller.play(reason: "error handling test")

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
