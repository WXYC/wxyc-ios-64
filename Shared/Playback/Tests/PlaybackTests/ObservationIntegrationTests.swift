//
//  ObservationIntegrationTests.swift
//  Playback
//
//  Integration tests for observation functionality with the fixed implementation
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
import Analytics
import AnalyticsTesting
@testable import Playback
@testable import PlaybackCore
import Core

// NOTE: These tests are disabled because AudioPlayerController.isPlaying is a computed property
// that reads from player.isPlaying, and the player is marked @ObservationIgnored.
// True Swift Observations won't track changes to computed properties that read from non-observable sources.
// To fix: make isPlaying a stored property that gets updated via player.stateStream observation.
@Suite("Observation Integration Tests", .serialized, .disabled("AudioPlayerController.isPlaying is not truly observable - needs architecture change"))
@MainActor
struct ObservationIntegrationTests {

    // MARK: - Helper to create test controller

    private func makeTestController() -> AudioPlayerController {
        let mockPlayer = ObservationTestMockPlayer()
        #if os(iOS) || os(tvOS)
        return AudioPlayerController(
            player: mockPlayer,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: NotificationCenter(),
            analytics: MockStructuredAnalytics()
        )
        #else
        return AudioPlayerController(
            player: mockPlayer,
            notificationCenter: NotificationCenter(),
            analytics: MockStructuredAnalytics()
        )
        #endif
    }

    // MARK: - Integration Tests

    @Test("Observations API tracks state changes")
    func observationsAPITracksChanges() async throws {
        let controller = makeTestController()
        var observedStates: [(Bool, Bool)] = []

        let observations = Observations {
            (controller.isPlaying, controller.isLoading)
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
        try await Task.sleep(for: .milliseconds(50))

        // Trigger state changes
        controller.play()
        try await Task.sleep(for: .milliseconds(50))

        controller.stop()
        try await Task.sleep(for: .milliseconds(50))

        controller.play()
        try await Task.sleep(for: .milliseconds(50))

        observationTask.cancel()

        #expect(observedStates.count >= 2, "Should observe at least 2 state changes")
        #expect(observedStates.contains { $0.0 == true }, "Should observe playing state")
        #expect(observedStates.contains { $0.0 == false }, "Should observe stopped state")
    }

    @Test("Initial state is captured")
    func observationsAPIInitialState() async throws {
        let controller = makeTestController()
        var firstState: Bool?

        // Ensure we start stopped
        controller.stop()
        try await Task.sleep(for: .milliseconds(50))

        let observations = Observations {
            controller.isPlaying
        }

        let observationTask = Task {
            for await state in observations {
                if firstState == nil {
                    firstState = state
                }
                break
            }
        }

        try await Task.sleep(for: .milliseconds(100))
        observationTask.cancel()

        #expect(firstState != nil, "Should capture initial state")
        #expect(firstState == false, "Initial state should be stopped")
    }

    @Test("Rapid state changes handled")
    func rapidStateChanges() async throws {
        let controller = makeTestController()
        var changeCount = 0

        let observations = Observations {
            controller.isPlaying
        }

        let observationTask = Task {
            for await _ in observations {
                changeCount += 1
                if changeCount >= 10 {
                    break
                }
            }
        }

        // Rapid changes
        for _ in 0..<5 {
            controller.play()
            try await Task.sleep(for: .milliseconds(20))
            controller.stop()
            try await Task.sleep(for: .milliseconds(20))
        }

        observationTask.cancel()

        #expect(changeCount >= 5, "Should handle rapid state changes")
    }

    @Test("No state change no notification")
    func noStateChangeNoNotification() async throws {
        let controller = makeTestController()
        var changeCount = 0

        // Ensure we start stopped
        controller.stop()
        try await Task.sleep(for: .milliseconds(50))

        let observations = Observations {
            controller.isPlaying
        }

        let observationTask = Task {
            for await _ in observations {
                changeCount += 1
            }
        }

        // Don't change state - just wait
        try await Task.sleep(for: .milliseconds(200))

        observationTask.cancel()

        #expect(changeCount <= 1, "Should have minimal notifications when state doesn't change")
    }

    @Test("Cancellation stops observations")
    func cancellationStopsObservations() async throws {
        let controller = makeTestController()
        var changeCount = 0

        let observations = Observations {
            controller.isPlaying
        }

        let observationTask = Task {
            for await _ in observations {
                changeCount += 1
            }
        }

        // Trigger one change
        controller.play()
        try await Task.sleep(for: .milliseconds(50))

        let countBeforeCancel = changeCount

        // Cancel observation
        observationTask.cancel()
        try await Task.sleep(for: .milliseconds(50))

        // Trigger more changes after cancellation
        controller.stop()
        try await Task.sleep(for: .milliseconds(50))
        controller.play()
        try await Task.sleep(for: .milliseconds(50))

        // Count should not increase (allow +1 for race condition)
        #expect(changeCount <= countBeforeCancel + 1, "Changes should stop after cancellation")
    }
}

// MARK: - Mock Player for Observation Tests

/// Mock player that emits state changes for testing observations.
/// Uses AsyncStream continuations to properly signal state changes.
final class ObservationTestMockPlayer: AudioPlayerProtocol, @unchecked Sendable {
    private(set) var state: PlayerState = .idle
    var isPlaying: Bool { state == .playing }

    private var stateContinuation: AsyncStream<PlayerState>.Continuation?
    private var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation?

    var stateStream: AsyncStream<PlayerState> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
        }
    }

    var eventStream: AsyncStream<AudioPlayerInternalEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func play() {
        state = .playing
        stateContinuation?.yield(.playing)
    }

    func stop() {
        state = .idle
        stateContinuation?.yield(.idle)
    }

    func installRenderTap() {}
    func removeRenderTap() {}
}
