//
//  ObservationIntegrationTests.swift
//  StreamingAudioPlayerTests
//
//  Integration tests for observation functionality with the fixed implementation
//

import Testing
import Foundation
@testable import Playback
@testable import PlaybackCore
import Core

@Suite("Observation Integration Tests", .serialized)
@MainActor
struct ObservationIntegrationTests {

    // MARK: - Integration Tests

    /// This test requires real audio infrastructure to verify isPlaying state transitions.
    /// It's disabled for package tests (macOS) where audio playback doesn't work.
    @Test("Observations API tracks state changes", .disabled("Requires iOS simulator with audio support"))
    func observationsAPITracksChanges() async throws {
        var observedStates: [(Bool, Bool)] = []

        let observations = Observations {
            (AudioPlayerController.shared.isPlaying, AudioPlayerController.shared.isLoading)
        }

        let observationTask = Task {
            for await state in observations {
                observedStates.append(state)
                if observedStates.count >= 3 {
                    break
                }
            }
        }

        // Give observation time to set up
        try await Task.sleep(for: .milliseconds(100))

        // Trigger state changes (AudioPlayerController already has a streamURL)
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        observationTask.cancel()

        #expect(observedStates.count >= 2, "Should observe at least 2 state changes")
        #expect(observedStates.contains { $0.0 == true }, "Should observe playing state")
        #expect(observedStates.contains { $0.0 == false }, "Should observe paused state")
    }

    @Test("Initial state is captured")
    func observationsAPIInitialState() async throws {
        var firstState: Bool?

        // Ensure we start paused
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(100))

        let observations = Observations {
            AudioPlayerController.shared.isPlaying
        }

        let observationTask = Task {
            for await state in observations {
                if firstState == nil {
                    firstState = state
                }
                break
            }
        }

        try await Task.sleep(for: .milliseconds(200))
        observationTask.cancel()

        #expect(firstState != nil, "Should capture initial state")
        #expect(firstState == false, "Initial state should be paused")
    }

    @Test("Rapid state changes handled")
    func rapidStateChanges() async throws {
        var changeCount = 0

        let observations = Observations {
            AudioPlayerController.shared.isPlaying
        }

        let observationTask = Task {
            for await _ in observations {
                changeCount += 1
                if changeCount >= 10 {
                    break
                }
            }
        }

        // Rapid changes (AudioPlayerController already has a streamURL)
        for _ in 0..<5 {
            AudioPlayerController.shared.play()
            try await Task.sleep(for: .milliseconds(50))
            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(50))
        }

        observationTask.cancel()

        #expect(changeCount >= 5, "Should handle rapid state changes")
    }

    @Test("No state change no notification")
    func noStateChangeNoNotification() async throws {
        var changeCount = 0

        // Create a fresh controller to isolate from other tests
        let controller = AudioPlayerController(
            notificationCenter: NotificationCenter(),
            analytics: MockPlaybackAnalytics()
        )

        // Ensure we start paused
        controller.pause()
        try await Task.sleep(for: .milliseconds(100))

        let observations = Observations {
            controller.isPlaying
        }

        let observationTask = Task {
            for await _ in observations {
                changeCount += 1
            }
        }

        // Don't change state - just wait
        try await Task.sleep(for: .milliseconds(500))

        observationTask.cancel()

        #expect(changeCount <= 1, "Should have minimal notifications when state doesn't change")
    }

    @Test("Cancellation stops observations")
    func cancellationStopsObservations() async throws {
        var changeCount = 0

        let observations = Observations {
            AudioPlayerController.shared.isPlaying
        }

        let observationTask = Task {
            for await _ in observations {
                changeCount += 1
            }
        }

        // Trigger one change (AudioPlayerController already has a streamURL)
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        let countBeforeCancel = changeCount

        // Cancel observation
        observationTask.cancel()
        try await Task.sleep(for: .milliseconds(100))

        // Trigger more changes after cancellation
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        // Count should not increase (allow +1 for race condition)
        #expect(changeCount <= countBeforeCancel + 1, "Changes should stop after cancellation")
    }
}
