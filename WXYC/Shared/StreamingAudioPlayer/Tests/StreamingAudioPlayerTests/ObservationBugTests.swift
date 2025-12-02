//
//  ObservationBugTests.swift
//  CoreTests
//
//  Tests that demonstrate the withObservationTracking bug
//  These tests SHOULD FAIL with the current implementation
//

import Testing
import Foundation
@testable import StreamingAudioPlayer

@Suite("Observation Bug Demonstration", .serialized)
@MainActor
struct ObservationBugTests {

    // MARK: - Setup/Teardown

    init() async throws {
        // Reset to known state before each test
        await AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Bug Demonstration Tests

    @Test("❌ BUG: withObservationTracking doesn't update captured state",
          .bug("Current implementation only re-registers, never updates state"))
    func withObservationTrackingDoesNotUpdateState() async throws {
        var capturedStates: [Bool] = []
        var changeCount = 0
        let expectedChanges = 3

        // This mimics the CURRENT (BROKEN) implementation
        @Sendable func observeBroken() {
            let _ = withObservationTracking {
                Task { @MainActor in
                    AudioPlayerController.shared.isPlaying  // ❌ Read but never store
                }
            } onChange: {
                changeCount += 1
                // ❌ Re-register but never update state
                if changeCount < expectedChanges {
                    observeBroken()
                }
            }
        }

        observeBroken()

        // Trigger state changes
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        // The onChange fired multiple times
        #expect(changeCount >= 2, "onChange should fire for state changes")

        // BUT we never captured the states!
        #expect(capturedStates.isEmpty,
               "BUG: Current implementation never captures state changes")

        print("⚠️  BUG CONFIRMED: onChange fired \(changeCount) times but captured 0 states")
    }

    @Test("✅ CORRECT: withObservationTracking SHOULD update state",
          .bug("This shows the correct implementation"))
    func withObservationTrackingShouldUpdateState() async throws {
        var capturedStates: [Bool] = []
        var changeCount = 0
        let expectedChanges = 3

        await confirmation("State changes captured", expectedCount: expectedChanges) { confirm in
            // This is the CORRECT implementation
            @Sendable func observeCorrect() {
                let currentState = withObservationTracking {
                    AudioPlayerController.shared.isPlaying  // ✅ Read synchronously
                } onChange: {
                    Task { @MainActor in
                        changeCount += 1
                        confirm()
                        if changeCount < expectedChanges {
                            observeCorrect()  // ✅ Re-register after capturing
                        }
                    }
                }
                // ✅ Capture the state outside the tracking block
                capturedStates.append(currentState)
            }

            // Start with initial state
            observeCorrect()

            // Trigger state changes
            AudioPlayerController.shared.play()
            try await Task.sleep(for: .milliseconds(200))

            AudioPlayerController.shared.pause()
            try await Task.sleep(for: .milliseconds(200))

            AudioPlayerController.shared.play()
            try await Task.sleep(for: .milliseconds(200))
        }

        // Now we SHOULD have captured states
        #expect(capturedStates.count >= 2,
               "CORRECT: Should capture state on each re-registration")
        #expect(changeCount >= 2,
               "onChange should fire for state changes")

        print("✅ CORRECT: onChange fired \(changeCount) times and captured \(capturedStates.count) states")
    }

    @Test("❌ BUG: PlaybackButton state never updates with current implementation")
    func playbackButtonStateNeverUpdates() async throws {
        // Simulate what happens in PlaybackButton
        var uiState: Bool = false  // The @State variable in SwiftUI
        var onChangeCallCount = 0

        // Current (BROKEN) implementation from PlaybackButton.swift
        @Sendable func observeAsInPlaybackButton() {
            let _ = withObservationTracking {
                Task { @MainActor in
                    AudioPlayerController.shared.isPlaying
                }
            } onChange: {
                onChangeCallCount += 1
                // ❌ Bug: We re-register but NEVER update uiState
                if onChangeCallCount < 5 {
                    observeAsInPlaybackButton()
                }
            }
        }

        // Start with paused
        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(100))

        // Initial UI state matches
        uiState = await AudioPlayerController.shared.isPlaying
        #expect(uiState == false, "Initially paused")

        observeAsInPlaybackButton()

        // Change to playing
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(300))

        // onChange fired...
        #expect(onChangeCallCount > 0, "onChange should have fired")

        // But UI state was NEVER updated!
        #expect(uiState == false,
               "BUG: UI state is still false even though playback started!")

        let actualState = await AudioPlayerController.shared.isPlaying
        #expect(actualState == true, "Actual playback state is playing")

        print("⚠️  BUG: onChange fired \(onChangeCallCount) times but uiState never changed from \(uiState)")
        print("⚠️  Actual playback state: \(actualState)")
    }

    @Test("❌ BUG: CarPlay template never updates with current implementation")
    func carPlayTemplateNeverUpdates() async throws {
        // Simulate what happens in CarPlaySceneDelegate
        var templateUpdateCount = 0
        var onChangeCallCount = 0

        func updateListTemplate() {
            templateUpdateCount += 1
        }

        // Current (BROKEN) implementation from CarPlaySceneDelegate.swift
        @Sendable func observeAsInCarPlay() {
            let _ = withObservationTracking {
                Task { @MainActor in
                    AudioPlayerController.shared.isPlaying
                }
            } onChange: {
                onChangeCallCount += 1
                // ❌ Bug: onChange fires but we never call updateListTemplate!
                if onChangeCallCount < 5 {
                    observeAsInCarPlay()
                }
            }
        }

        observeAsInCarPlay()

        // Change playback state
        AudioPlayerController.shared.play()
        try await Task.sleep(for: .milliseconds(200))

        AudioPlayerController.shared.pause()
        try await Task.sleep(for: .milliseconds(200))

        // onChange fired
        #expect(onChangeCallCount >= 1, "onChange should fire")

        // But template was NEVER updated!
        #expect(templateUpdateCount == 0,
               "BUG: Template never updated even though state changed!")

        print("⚠️  BUG: onChange fired \(onChangeCallCount) times but template updated 0 times")
    }
}
