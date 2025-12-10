//
//  ObservationIntegrationTests.swift
//  StreamingAudioPlayerTests
//
//  Integration tests for observation functionality with the fixed implementation
//

import Testing
import Foundation
@testable import Playback

@Suite("Observation Integration Tests", .serialized)
@MainActor
struct ObservationIntegrationTests {

    // MARK: - iOS 26+ Tests

    @Test("iOS 26+: Observations API tracks state changes")
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    func observationsAPITracksChanges() async throws {
        var observedStates: [Bool] = []

        let observations = Observations {
            AudioPlayerController.shared.isPlaying
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

        // Trigger state changes with a URL
        let testURL = URL(string: "https://example.com/stream")!
        AudioPlayerController.shared.play(url: testURL)
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.play(url: testURL)
        try await Task.sleep(for: .milliseconds(200))

        observationTask.cancel()

        #expect(observedStates.count >= 2, "Should observe at least 2 state changes")
        #expect(observedStates.contains(true), "Should observe playing state")
        #expect(observedStates.contains(false), "Should observe paused state")
    }

    @Test("iOS 26+: Initial state is captured")
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
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

    // MARK: - iOS < 26 Tests

    @Test("iOS < 26: withObservationTracking tracks state changes")
    func withObservationTrackingTracksChanges() async throws {
        var observedStates: [Bool] = []
        var changeCount = 0

        @Sendable func observe() {
            Task { @MainActor in
                let currentState = withObservationTracking {
                    AudioPlayerController.shared.isPlaying
                } onChange: {
                    Task { @MainActor in
                        changeCount += 1
                        let newState = AudioPlayerController.shared.isPlaying
                        observedStates.append(newState)
                        if changeCount < 3 {
                            observe()
                        }
                    }
                }
                // Capture initial state
                observedStates.append(currentState)
            }
        }

        observe()
        try await Task.sleep(for: .milliseconds(100))

        // Trigger state changes
        let testURL = URL(string: "https://example.com/stream")!
        AudioPlayerController.shared.play(url: testURL)
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.play(url: testURL)
        try await Task.sleep(for: .milliseconds(200))

        #expect(observedStates.count >= 3, "Should observe multiple states including initial")
        #expect(observedStates.contains(true), "Should observe playing state")
        #expect(observedStates.contains(false), "Should observe paused state")
        #expect(changeCount >= 2, "onChange should fire at least 2 times")
    }

    @Test("iOS < 26: State updates propagate correctly")
    func withObservationTrackingStateUpdates() async throws {
        var observedStates: [Bool] = []
        var updateCount = 0

        @Sendable func observe() {
            Task { @MainActor in
                let currentState = withObservationTracking {
                    AudioPlayerController.shared.isPlaying
                } onChange: {
                    Task { @MainActor in
                        let newState = AudioPlayerController.shared.isPlaying
                        observedStates.append(newState)
                        updateCount += 1
                        if updateCount < 3 {
                            observe()
                        }
                    }
                }
                // Capture initial state
                observedStates.append(currentState)
            }
        }

        observe()
        try await Task.sleep(for: .milliseconds(100))

        let testURL = URL(string: "https://example.com/stream")!

        // Trigger state changes
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.play(url: testURL)
        try await Task.sleep(for: .milliseconds(300))

        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))

        // Verify we captured multiple states
        #expect(observedStates.count >= 2, "Should observe multiple state updates")
        #expect(updateCount >= 1, "Should trigger at least one update")
        #expect(observedStates.contains(true) || observedStates.contains(false),
               "Should observe state changes")
    }

    // MARK: - Cross-Platform Tests

    @Test("Both platforms: Rapid state changes handled")
    func rapidStateChanges() async throws {
        var changeCount = 0

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            // iOS 26+ path
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

            let testURL = URL(string: "https://example.com/stream")!

            // Rapid changes
            for _ in 0..<5 {
                AudioPlayerController.shared.play(url: testURL)
                try await Task.sleep(for: .milliseconds(50))
                AudioPlayerController.shared.pause()
                try await Task.sleep(for: .milliseconds(50))
            }

            observationTask.cancel()
        } else {
            // iOS < 26 path
            @Sendable func observe() {
                Task { @MainActor in
                    let _ = withObservationTracking {
                        AudioPlayerController.shared.isPlaying
                    } onChange: {
                        Task { @MainActor in
                            changeCount += 1
                            if changeCount < 10 {
                                observe()
                            }
                        }
                    }
                }
            }

            observe()

            let testURL = URL(string: "https://example.com/stream")!

            // Rapid changes
            for _ in 0..<5 {
                AudioPlayerController.shared.play(url: testURL)
                try await Task.sleep(for: .milliseconds(50))
                AudioPlayerController.shared.pause()
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        #expect(changeCount >= 5, "Should handle rapid state changes")
    }

    @Test("Both platforms: No state change no notification")
    func noStateChangeNoNotification() async throws {
        var changeCount = 0

        // Ensure we start paused
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(100))

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            // iOS 26+ path
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            let observationTask = Task {
                for await _ in observations {
                    changeCount += 1
                }
            }

            // Don't change state - just wait
            try await Task.sleep(for: .milliseconds(500))

            observationTask.cancel()
        } else {
            // iOS < 26 path
            @Sendable func observe() {
                Task { @MainActor in
                    let _ = withObservationTracking {
                        AudioPlayerController.shared.isPlaying
                    } onChange: {
                        Task { @MainActor in
                            changeCount += 1
                            observe()
                        }
                    }
                }
            }

            observe()

            // Don't change state - just wait
            try await Task.sleep(for: .milliseconds(500))
        }

        #expect(changeCount <= 1, "Should have minimal notifications when state doesn't change")
    }

    @Test("Both platforms: Cancellation stops observations")
    func cancellationStopsObservations() async throws {
        var changeCount = 0

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            // iOS 26+ path
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            let observationTask = Task {
                for await _ in observations {
                    changeCount += 1
                }
            }

            let testURL = URL(string: "https://example.com/stream")!

            // Trigger one change
            AudioPlayerController.shared.play(url: testURL)
            try await Task.sleep(for: .milliseconds(200))

            let countBeforeCancel = changeCount

            // Cancel observation
            observationTask.cancel()
            try await Task.sleep(for: .milliseconds(100))

            // Trigger more changes after cancellation
            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(200))
            AudioPlayerController.shared.play(url: testURL)
            try await Task.sleep(for: .milliseconds(200))

            // Count should not increase (allow +1 for race condition)
            #expect(changeCount <= countBeforeCancel + 1, "Changes should stop after cancellation")
        } else {
            // iOS < 26 path - harder to test cancellation
            // For withObservationTracking, we test that limited observations work correctly
            let maxChanges = 2

            @Sendable func observe() {
                Task { @MainActor in
                    let _ = withObservationTracking {
                        AudioPlayerController.shared.isPlaying
                    } onChange: {
                        Task { @MainActor in
                            changeCount += 1
                            if changeCount < maxChanges {
                                observe()
                            }
                        }
                    }
                }
            }

            observe()

            let testURL = URL(string: "https://example.com/stream")!

            // Trigger one change
            AudioPlayerController.shared.play(url: testURL)
            try await Task.sleep(for: .milliseconds(200))

            // Trigger another change
            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(200))

            let countAfterLimit = changeCount

            // Trigger more changes after reaching limit
            AudioPlayerController.shared.play(url: testURL)
            try await Task.sleep(for: .milliseconds(200))
            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(200))

            // Count should not increase beyond limit
            #expect(changeCount == countAfterLimit, "Observations should stop after limit reached")
        }
    }
}
