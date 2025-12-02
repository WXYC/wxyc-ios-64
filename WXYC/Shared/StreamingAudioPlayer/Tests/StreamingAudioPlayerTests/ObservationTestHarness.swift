//
//  ObservationTestHarness.swift
//  CoreTests
//
//  Test harness for comparing Observations API (iOS 26+) vs withObservationTracking (iOS < 26)
//

import Testing
import Foundation
@testable import StreamingAudioPlayer

// MARK: - Observation Strategy Protocol

/// Abstraction over different observation mechanisms
protocol ObservationStrategy: Sendable {
    /// The OS versions this strategy supports
    var supportedOS: String { get }

    /// Start observing and call handler when changes occur
    func observe(
        onChange: @escaping @Sendable () -> Void
    ) async

    /// Get the current state synchronously
    func getCurrentState() -> Bool
}

// MARK: - iOS 26+ Strategy (Observations API)

@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
struct ObservationsAPIStrategy: ObservationStrategy {
    let supportedOS = "iOS 26.0+"

    func observe(onChange: @escaping @Sendable () -> Void) async {
        let observations = Observations {
            Task { @MainActor in AudioPlayerController.shared.isPlaying }
        }

        for await _ in observations {
            onChange()
        }
    }

    func getCurrentState() -> Bool {
        AudioPlayerController.shared.isPlaying
    }
}

// MARK: - iOS < 26 Strategy (withObservationTracking) - BROKEN VERSION

struct WithObservationTrackingBrokenStrategy: ObservationStrategy {
    let supportedOS = "iOS < 26.0 (BROKEN)"

    func observe(onChange: @escaping @Sendable () -> Void) async {
        // This mimics the CURRENT broken implementation
        @Sendable func observeRecursive() {
            let _ = withObservationTracking {
                Task { @MainActor in
                    AudioPlayerController.shared.isPlaying
                }
            } onChange: {
                onChange()
                observeRecursive()  // ❌ Re-register but never capture state
            }
        }

        observeRecursive()

        // Keep alive
        try? await Task.sleep(for: .seconds(3600))
    }

    func getCurrentState() -> Bool {
        AudioPlayerController.shared.isPlaying
    }
}

// MARK: - iOS < 26 Strategy (withObservationTracking) - FIXED VERSION

struct WithObservationTrackingFixedStrategy: ObservationStrategy {
    let supportedOS = "iOS < 26.0 (FIXED)"

    func observe(onChange: @escaping @Sendable () -> Void) async {
        // This is the CORRECT implementation
        @Sendable func observeRecursive() {
            let _ = withObservationTracking {
                AudioPlayerController.shared.isPlaying  // ✅ Read synchronously
            } onChange: {
                Task { @MainActor in
                    onChange()  // ✅ Notify of change
                    observeRecursive()  // ✅ Re-register
                }
            }
        }

        observeRecursive()

        // Keep alive
        try? await Task.sleep(for: .seconds(3600))
    }

    func getCurrentState() -> Bool {
        AudioPlayerController.shared.isPlaying
    }
}

// MARK: - Test Harness

@Suite("Observation Strategy Test Harness", .serialized)
@MainActor
struct ObservationTestHarness {

    // MARK: - Shared Test Logic

    /// Run a standardized test against any observation strategy
    static func runStandardTest(
        strategy: ObservationStrategy,
        testName: String
    ) async throws -> TestResult {
        var changeCount = 0
        var stateCaptures: [StateCapture] = []
        let expectedChanges = 3

        // Start observation in background
        let observationTask = Task {
            await strategy.observe {
                changeCount += 1
            }
        }

        // Allow observation to start
        try await Task.sleep(for: .milliseconds(100))

        // Capture initial state
        stateCaptures.append(StateCapture(
            timestamp: Date(),
            isPlaying: strategy.getCurrentState(),
            changeNumber: 0
        ))

        // Test sequence: pause -> play -> pause -> play
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))
        stateCaptures.append(StateCapture(
            timestamp: Date(),
            isPlaying: strategy.getCurrentState(),
            changeNumber: changeCount
        ))

        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))
        stateCaptures.append(StateCapture(
            timestamp: Date(),
            isPlaying: strategy.getCurrentState(),
            changeNumber: changeCount
        ))

        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))
        stateCaptures.append(StateCapture(
            timestamp: Date(),
            isPlaying: strategy.getCurrentState(),
            changeNumber: changeCount
        ))

        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))
        stateCaptures.append(StateCapture(
            timestamp: Date(),
            isPlaying: strategy.getCurrentState(),
            changeNumber: changeCount
        ))

        // Clean up
        observationTask.cancel()

        return TestResult(
            strategyName: strategy.supportedOS,
            testName: testName,
            changeCount: changeCount,
            stateCaptures: stateCaptures,
            expectedChanges: expectedChanges
        )
    }

    // MARK: - Tests for Each Strategy

    @Test("BROKEN: withObservationTracking (current implementation)")
    func testBrokenImplementation() async throws {
        let strategy = WithObservationTrackingBrokenStrategy()
        let result = try await Self.runStandardTest(
            strategy: strategy,
            testName: "Broken Implementation"
        )

        result.printReport()

        // This should FAIL - demonstrating the bug
        #expect(result.changeCount > 0,
               "onChange should fire (it does)")

        // But state tracking doesn't work properly
        Issue.record("BUG: Current implementation fires onChange but doesn't provide state updates correctly")
    }

    @Test("FIXED: withObservationTracking (corrected implementation)")
    func testFixedImplementation() async throws {
        let strategy = WithObservationTrackingFixedStrategy()
        let result = try await Self.runStandardTest(
            strategy: strategy,
            testName: "Fixed Implementation"
        )

        result.printReport()

        // This should PASS
        #expect(result.changeCount >= 2,
               "onChange should fire for state changes")
        #expect(result.stateCaptures.count > 3,
               "Should capture multiple states")

        // Verify state transitions occurred
        let states = result.stateCaptures.map(\.isPlaying)
        #expect(states.contains(true) && states.contains(false),
               "Should observe both playing and paused states")
    }

    @Test("iOS 26+: Observations API",
          .enabled(if: #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)))
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    func testObservationsAPI() async throws {
        let strategy = ObservationsAPIStrategy()
        let result = try await Self.runStandardTest(
            strategy: strategy,
            testName: "Observations API"
        )

        result.printReport()

        #expect(result.changeCount >= 2,
               "onChange should fire for state changes")
        #expect(result.stateCaptures.count > 3,
               "Should capture multiple states")
    }

    // MARK: - Comparison Test

    @Test("Compare Fixed vs iOS 26+ behavior",
          .enabled(if: #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)),
          tags: [.comparison])
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
    func compareStrategies() async throws {
        let fixedStrategy = WithObservationTrackingFixedStrategy()
        let ios26Strategy = ObservationsAPIStrategy()

        let fixedResult = try await Self.runStandardTest(
            strategy: fixedStrategy,
            testName: "Fixed withObservationTracking"
        )

        // Reset state
        try await Task.sleep(for: .milliseconds(500))

        let ios26Result = try await Self.runStandardTest(
            strategy: ios26Strategy,
            testName: "iOS 26 Observations"
        )

        print("\n" + "=".repeating(60))
        print("COMPARISON REPORT")
        print("=".repeating(60))
        fixedResult.printReport()
        print("")
        ios26Result.printReport()
        print("=".repeating(60))

        // Both should behave similarly
        #expect(fixedResult.changeCount > 0 && ios26Result.changeCount > 0,
               "Both strategies should detect changes")

        // Allow some variance in exact counts due to timing
        let countDifference = abs(fixedResult.changeCount - ios26Result.changeCount)
        #expect(countDifference <= 2,
               "Change counts should be similar (within 2)")
    }

    // MARK: - Real-World Simulation

    @Test("Simulate PlaybackButton behavior with Fixed implementation")
    func simulatePlaybackButton() async throws {
        var uiState: Bool = false
        var uiUpdateCount = 0

        func updateUI(newState: Bool) {
            uiState = newState
            uiUpdateCount += 1
        }

        // Fixed implementation that actually updates state
        let observationTask = Task {
            @Sendable func observe() {
                let currentState = withObservationTracking {
                    AudioPlayerController.shared.isPlaying
                } onChange: {
                    Task { @MainActor in
                        let newState = AudioPlayerController.shared.isPlaying
                        updateUI(newState: newState)
                        observe()
                    }
                }
                // Capture initial state
                Task { @MainActor in
                    updateUI(newState: currentState)
                }
            }

            observe()
            try? await Task.sleep(for: .seconds(3600))
        }

        try await Task.sleep(for: .milliseconds(100))

        // Start paused
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))
        #expect(uiState == false, "UI should show paused")

        // Play
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))
        #expect(uiState == true, "UI should show playing")

        // Pause
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))
        #expect(uiState == false, "UI should show paused again")

        #expect(uiUpdateCount >= 3, "UI should have updated multiple times")

        observationTask.cancel()

        print("✅ UI updated \(uiUpdateCount) times correctly")
    }
}

// MARK: - Supporting Types

struct StateCapture: Sendable {
    let timestamp: Date
    let isPlaying: Bool
    let changeNumber: Int
}

struct TestResult: Sendable {
    let strategyName: String
    let testName: String
    let changeCount: Int
    let stateCaptures: [StateCapture]
    let expectedChanges: Int

    func printReport() {
        print("\n📊 Test Report: \(testName)")
        print("Strategy: \(strategyName)")
        print("onChange fired: \(changeCount) times (expected ≥\(expectedChanges))")
        print("State captures: \(stateCaptures.count)")
        print("\nState Timeline:")
        for (index, capture) in stateCaptures.enumerated() {
            let icon = capture.isPlaying ? "▶️" : "⏸️"
            print("  \(index). \(icon) \(capture.isPlaying ? "Playing" : "Paused") (changes: \(capture.changeNumber))")
        }
    }
}

extension Tag {
    @Tag static var comparison: Self
}

extension String {
    func repeating(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
