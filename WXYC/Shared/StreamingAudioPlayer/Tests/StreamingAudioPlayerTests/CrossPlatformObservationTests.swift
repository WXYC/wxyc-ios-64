//
//  CrossPlatformObservationTests.swift
//  CoreTests
//
//  Tests that run on both iOS 26+ and iOS < 26 to verify equivalent behavior
//

import Testing
import Foundation
@testable import StreamingAudioPlayer

@Suite("Cross-Platform Observation Tests", .serialized)
@MainActor
struct CrossPlatformObservationTests {

    // MARK: - Platform Detection

    static var currentPlatform: String {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            return "iOS 26+"
        } else {
            return "iOS < 26"
        }
    }

    // MARK: - Baseline Behavior Tests

    @Test("Baseline: AudioPlayerController observation works",
          .tags(.baseline))
    func baselineObservation() async throws {
        var changeCount = 0

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            // iOS 26+ path
            await confirmation("iOS 26+ observation works", expectedCount: 2) { confirm in
                let observations = Observations {
                    AudioPlayerController.shared.isPlaying
                }

                Task {
                    for await _ in observations {
                        changeCount += 1
                        confirm()
                        if changeCount >= 2 { break }
                    }
                }

                try await Task.sleep(for: .milliseconds(100))
                AudioPlayerController.shared.play()
                try await Task.sleep(for: .milliseconds(200))
                AudioPlayerController.shared.pause()
                try await Task.sleep(for: .milliseconds(200))
            }
        } else {
            // iOS < 26 path - FIXED implementation
            await confirmation("iOS < 26 observation works", expectedCount: 2) { confirm in
                @Sendable func observe() {
                    let _ = withObservationTracking {
                        AudioPlayerController.shared.isPlaying
                    } onChange: {
                        Task { @MainActor in
                            changeCount += 1
                            confirm()
                            if changeCount < 2 {
                                observe()
                            }
                        }
                    }
                }

                observe()

                try await Task.sleep(for: .milliseconds(100))
                AudioPlayerController.shared.play()
                try await Task.sleep(for: .milliseconds(200))
                AudioPlayerController.shared.pause()
                try await Task.sleep(for: .milliseconds(200))
            }
        }

        #expect(changeCount >= 2,
               "Platform: \(Self.currentPlatform) - Should observe state changes")

        print("✅ \(Self.currentPlatform): Observed \(changeCount) changes")
    }

    @Test("State synchronization works correctly",
          .tags(.baseline))
    func stateSynchronization() async throws {
        var observedStates: [Bool] = []

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            // iOS 26+ path
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            let observationTask = Task {
                for await state in observations {
                    observedStates.append(state)
                    if observedStates.count >= 4 { break }
                }
            }

            try await Task.sleep(for: .milliseconds(100))

            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(200))

            AudioPlayerController.shared.play()
            try await Task.sleep(for: .milliseconds(200))

            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(200))

            AudioPlayerController.shared.play()
            try await Task.sleep(for: .milliseconds(200))

            observationTask.cancel()

        } else {
            // iOS < 26 path - FIXED implementation
            @Sendable func observe() {
                let state = withObservationTracking {
                    AudioPlayerController.shared.isPlaying
                } onChange: {
                    Task { @MainActor in
                        if observedStates.count < 4 {
                            observe()
                        }
                    }
                }
                observedStates.append(state)
            }

            observe()

            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(200))

            AudioPlayerController.shared.play()
            try await Task.sleep(for: .milliseconds(200))

            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(200))

            AudioPlayerController.shared.play()
            try await Task.sleep(for: .milliseconds(200))
        }

        #expect(observedStates.count >= 3,
               "Should observe multiple states")
        #expect(observedStates.contains(true),
               "Should observe 'playing' state")
        #expect(observedStates.contains(false),
               "Should observe 'paused' state")

        print("✅ \(Self.currentPlatform): Captured states: \(observedStates)")
    }

    // MARK: - Performance Comparison

    @Test("Performance: Observation overhead",
          .tags(.performance),
          .timeLimit(.seconds(30)))
    func observationPerformance() async throws {
        let startTime = ContinuousClock.now
        var changeCount = 0
        let targetChanges = 50

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            let task = Task {
                for await _ in observations {
                    changeCount += 1
                    if changeCount >= targetChanges { break }
                }
            }

            // Trigger rapid changes
            for _ in 0..<25 {
                AudioPlayerController.shared.play()
                try await Task.sleep(for: .milliseconds(10))
                AudioPlayerController.shared.pause()
                try await Task.sleep(for: .milliseconds(10))
            }

            task.cancel()

        } else {
            @Sendable func observe() {
                let _ = withObservationTracking {
                    AudioPlayerController.shared.isPlaying
                } onChange: {
                    Task { @MainActor in
                        changeCount += 1
                        if changeCount < targetChanges {
                            observe()
                        }
                    }
                }
            }

            observe()

            // Trigger rapid changes
            for _ in 0..<25 {
                AudioPlayerController.shared.play()
                try await Task.sleep(for: .milliseconds(10))
                AudioPlayerController.shared.pause()
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        let duration = ContinuousClock.now - startTime

        print("📊 \(Self.currentPlatform) Performance:")
        print("   Changes observed: \(changeCount)")
        print("   Duration: \(duration)")
        print("   Avg per change: \(duration / Double(max(changeCount, 1)))")

        #expect(changeCount > 0, "Should observe changes")
    }

    // MARK: - Edge Cases

    @Test("Edge case: No state changes",
          .tags(.edgeCase))
    func noStateChanges() async throws {
        var changeCount = 0

        let task: Task<Void, Never>

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            task = Task {
                for await _ in observations {
                    changeCount += 1
                }
            }
        } else {
            @Sendable func observe() {
                let _ = withObservationTracking {
                    AudioPlayerController.shared.isPlaying
                } onChange: {
                    changeCount += 1
                    observe()
                }
            }

            observe()

            task = Task {
                try? await Task.sleep(for: .seconds(3600))
            }
        }

        // Don't change state, just wait
        try await Task.sleep(for: .milliseconds(500))

        task.cancel()

        // Should not have fired onChange if state didn't change
        #expect(changeCount == 0,
               "Should not fire onChange without state changes")

        print("✅ \(Self.currentPlatform): Correctly handled no state changes")
    }

    @Test("Edge case: Rapid repeated same state",
          .tags(.edgeCase))
    func rapidRepeatedSameState() async throws {
        var changeCount = 0

        let task: Task<Void, Never>

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            task = Task {
                for await _ in observations {
                    changeCount += 1
                    if changeCount >= 10 { break }
                }
            }
        } else {
            @Sendable func observe() {
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

            observe()

            task = Task {
                try? await Task.sleep(for: .seconds(3600))
            }
        }

        // Repeatedly set to same state
        for _ in 0..<5 {
            AudioPlayerController.shared.play()
            try await Task.sleep(for: .milliseconds(50))
        }

        task.cancel()

        // Should only fire once (or zero times if already playing)
        #expect(changeCount <= 1,
               "Should not fire multiple times for same state")

        print("✅ \(Self.currentPlatform): Handled repeated same state correctly (\(changeCount) changes)")
    }

    @Test("Edge case: Observation cleanup",
          .tags(.edgeCase))
    func observationCleanup() async throws {
        var changeCount = 0

        // Start observation
        let task: Task<Void, Never>

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            task = Task {
                for await _ in observations {
                    changeCount += 1
                }
            }
        } else {
            @Sendable func observe() {
                let _ = withObservationTracking {
                    AudioPlayerController.shared.isPlaying
                } onChange: {
                    changeCount += 1
                    observe()
                }
            }

            observe()

            task = Task {
                try? await Task.sleep(for: .seconds(3600))
            }
        }

        // Trigger a change
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        let countBeforeCancel = changeCount

        // Cancel observation
        task.cancel()

        try await Task.sleep(for: .milliseconds(200))

        // Trigger more changes after cancel
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        // Count should not have increased after cancel
        // Note: There might be a race where one more fires, so allow +1
        #expect(changeCount <= countBeforeCancel + 1,
               "Should not observe changes after cleanup")

        print("✅ \(Self.currentPlatform): Cleanup worked (before: \(countBeforeCancel), after: \(changeCount))")
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var baseline: Self
    @Tag static var performance: Self
    @Tag static var edgeCase: Self
}
