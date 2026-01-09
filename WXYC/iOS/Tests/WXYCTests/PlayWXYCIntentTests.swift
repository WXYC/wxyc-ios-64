//
//  PlayWXYCIntentTests.swift
//  WXYCTests
//
//  Unit tests for PlayWXYC intent.
//  Tests that calling perform() directly triggers playback.
//

import AppIntents
import Testing
import Foundation
import UIKit
@testable import WXYC
@testable import Playback

@Suite("PlayWXYC Intent Tests", .serialized)
@MainActor
struct PlayWXYCIntentTests {

    @Test("perform() starts playback")
    func performStartsPlayback() async throws {
        // Ensure we start from a stopped state
        AudioPlayerController.shared.stop()
        try await Task.sleep(for: .milliseconds(200))

        #expect(!AudioPlayerController.shared.isPlaying, "Should start in stopped state")

        // Call the intent's perform method directly
        let intent = PlayWXYC()
        _ = try await intent.perform()

        // Wait for playback to initialize (poll with timeout)
        try await waitForPlayback(timeout: .seconds(5))

        // Verify playback started
        #expect(AudioPlayerController.shared.isPlaying, "Intent should have started playback")

        // Clean up: stop playback
        AudioPlayerController.shared.stop()
    }

    @Test("perform() starts playback from background")
    func performStartsPlaybackFromBackground() async throws {
        // Ensure we start from a stopped state
        AudioPlayerController.shared.stop()
        try await Task.sleep(for: .milliseconds(200))

        #expect(!AudioPlayerController.shared.isPlaying, "Should start in stopped state")

        // Simulate app entering background
        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        AudioPlayerController.shared.handleAppDidEnterBackground()

        // Wait for background transition
        try await Task.sleep(for: .milliseconds(100))

        // Call the intent's perform method while "backgrounded"
        // This simulates what happens when Siri/Shortcuts triggers the intent
        let intent = PlayWXYC()
        _ = try await intent.perform()

        // Wait for playback to initialize (poll with timeout)
        try await waitForPlayback(timeout: .seconds(5))

        // Verify playback started even from background
        #expect(AudioPlayerController.shared.isPlaying, "Intent should start playback from background")

        // Simulate returning to foreground
        NotificationCenter.default.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        AudioPlayerController.shared.handleAppWillEnterForeground()

        // Verify still playing after foregrounding
        #expect(AudioPlayerController.shared.isPlaying, "Playback should continue after foregrounding")

        // Clean up
        AudioPlayerController.shared.stop()
    }

    @Test("perform() returns correct dialog")
    func performReturnsCorrectDialog() async throws {
        let intent = PlayWXYC()
        let result = try await intent.perform()

        // The result value should be the tuning message
        #expect(result.value == "Tuning in to WXYC…", "Should return tuning message")

        // Clean up
        AudioPlayerController.shared.stop()
    }

    @Test("perform() is idempotent when already playing")
    func performIdempotentWhenPlaying() async throws {
        // Start playback first
        await AudioPlayerController.shared.play()
        try await waitForPlayback(timeout: .seconds(5))

        let wasPlaying = AudioPlayerController.shared.isPlaying

        // Call perform again
        let intent = PlayWXYC()
        _ = try await intent.perform()

        try await Task.sleep(for: .milliseconds(100))

        // Should still be playing (no crash, no state change)
        #expect(AudioPlayerController.shared.isPlaying == wasPlaying, "State should remain consistent")

        // Clean up
        AudioPlayerController.shared.stop()
    }
}

// MARK: - Test Helpers

/// Waits for playback to start, polling isPlaying with a timeout.
@MainActor
private func waitForPlayback(timeout: Duration) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !AudioPlayerController.shared.isPlaying {
        if clock.now >= deadline {
            // Don't throw - just return and let the test assertion handle it
            return
        }
        try await Task.sleep(for: .milliseconds(100))
    }
}
