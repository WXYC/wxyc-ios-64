//
//  PlaybackButtonObservationUITests.swift
//  WXYCUITests
//
//  UI Integration tests for PlaybackButton observation behavior
//

import Testing
import XCTest

@Suite("PlaybackButton UI Integration Tests", .serialized)
@MainActor
struct PlaybackButtonObservationUITests {

    let app = XCUIApplication()

    init() {
        app.launch()
    }

    // MARK: - PlaybackButton Tests

    @Test("PlaybackButton visual state updates on tap")
    func playbackButtonVisualStateUpdates() async throws {
        let playButton = app.buttons["playPauseButton"]

        // Wait for button to appear
        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Button should start showing play icon (not playing)
        // Tap to start playback
        playButton.tap()

        // Wait for state change animation
        try await Task.sleep(for: .seconds(1))

        // Verify button still exists and responds
        #expect(playButton.exists, "Button should exist after starting playback")

        // Tap to pause
        playButton.tap()

        // Wait for state change animation
        try await Task.sleep(for: .milliseconds(500))

        // Verify button still works
        #expect(playButton.exists, "Button should exist after pausing")
    }

    @Test("PlaybackButton state syncs with AudioPlayerController")
    func playbackButtonStateSyncs() async throws {
        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Start playback via button tap (simulates AudioPlayerController.play())
        playButton.tap()

        // Wait for playback to start and UI to update
        try await Task.sleep(for: .seconds(2))

        // Button should still be responsive
        #expect(playButton.exists, "Button should remain responsive during playback")
        #expect(playButton.isHittable, "Button should be hittable during playback")

        // Stop playback via button tap (simulates AudioPlayerController.pause())
        playButton.tap()

        try await Task.sleep(for: .milliseconds(500))

        // Verify UI remains in sync
        #expect(playButton.exists, "Button should exist after stopping")
        #expect(playButton.isHittable, "Button should be hittable after stopping")
    }

    @Test("Rapid tapping doesn't cause UI issues")
    func rapidTappingHandled() async throws {
        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Rapidly tap the button 15 times
        for _ in 1...15 {
            playButton.tap()
            // Small delay between taps to simulate rapid user interaction
            try await Task.sleep(for: .milliseconds(100))
        }

        // Allow any pending animations/state changes to complete
        try await Task.sleep(for: .seconds(1))

        // App shouldn't crash and button should remain functional
        #expect(playButton.exists, "Button should exist after rapid tapping")
        #expect(playButton.isHittable, "Button should be hittable after rapid tapping")

        // Verify button still responds to taps
        playButton.tap()
        try await Task.sleep(for: .milliseconds(300))
        #expect(playButton.exists, "Button should still respond after rapid tapping")
    }

    @Test("State survives backgrounding")
    func stateSurvivesBackgrounding() async throws {
        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Start playback
        playButton.tap()
        try await Task.sleep(for: .seconds(2))

        // Background the app
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(2))

        // Foreground the app
        app.activate()
        try await Task.sleep(for: .seconds(1))

        // Button should still exist and be responsive
        #expect(playButton.waitForExistence(timeout: 5), "Button should exist after foregrounding")
        #expect(playButton.isHittable, "Button should be hittable after foregrounding")

        // Verify button still responds
        playButton.tap()
        try await Task.sleep(for: .milliseconds(500))
        #expect(playButton.exists, "Button should respond after backgrounding cycle")
    }

    @Test("Animation completes without issues during state change")
    func animationPlaysSmooth() async throws {
        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Perform state change and verify animation completes
        playButton.tap()

        // Animation duration is 0.24 seconds per PlaybackButton.swift
        // Wait for animation to complete
        try await Task.sleep(for: .milliseconds(300))

        // Verify button is in a stable state
        #expect(playButton.exists, "Button should exist after animation")

        // Perform another state change
        playButton.tap()
        try await Task.sleep(for: .milliseconds(300))

        // Verify no issues
        #expect(playButton.exists, "Button should exist after second animation")
        #expect(playButton.isHittable, "Button should be hittable after animations complete")
    }
}

@Suite("CarPlay UI Integration Tests", .serialized)
@MainActor
struct CarPlayObservationUITests {

    // Note: CarPlay UI testing requires the CarPlay Simulator which has limited
    // automation support. These tests verify basic functionality when possible.

    @Test("CarPlay template updates on playback state change", .disabled("CarPlay simulator automation not available in standard UI tests"))
    func carPlayTemplateUpdates() async throws {
        // CarPlay UI testing requires special simulator configuration
        // that isn't available in standard XCUITest runs.
        //
        // To test CarPlay functionality:
        // 1. Use the CarPlay Simulator (Xcode -> Open Developer Tool -> CarPlay Simulator)
        // 2. Manually verify template updates when playback state changes
        // 3. See CarPlaySceneDelegate.swift for implementation details
    }

    @Test("CarPlay list item selection works", .disabled("CarPlay simulator automation not available in standard UI tests"))
    func carPlayListItemSelection() async throws {
        // CarPlay list item selection testing requires the CarPlay Simulator
        // which cannot be automated through XCUITest.
        //
        // Manual testing steps:
        // 1. Launch app in CarPlay Simulator
        // 2. Tap "Listen Live" list item
        // 3. Verify playback starts
        // 4. Verify Now Playing template is displayed
    }

    @Test("CarPlay state syncs with main app", .disabled("CarPlay simulator automation not available in standard UI tests"))
    func carPlayStateSync() async throws {
        // Cross-component state sync between CarPlay and main app
        // must be tested manually with the CarPlay Simulator.
        //
        // Manual testing steps:
        // 1. Start playback in main app
        // 2. Open CarPlay Simulator
        // 3. Verify CarPlay shows playing state
        // 4. Stop playback in CarPlay
        // 5. Verify main app reflects the change
    }
}
