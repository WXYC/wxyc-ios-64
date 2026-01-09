//
//  PlayWXYCIntentUITests.swift
//  WXYCUITests
//
//  UI tests for verifying PlayWXYC intent and deep link playback triggers.
//

import Testing
import XCTest

@Suite("PlayWXYC Intent UI Tests", .serialized)
@MainActor
struct PlayWXYCIntentUITests {

    let app = XCUIApplication()

    init() {
        app.launch()
    }

    // MARK: - Deep Link Playback Tests (Enabled)

    @Test("Deep link triggers playback from background")
    func deepLinkTriggersPlaybackFromBackground() async throws {
        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Ensure we're starting from a stopped state
        if playButton.value as? String == "playing" {
            playButton.tap()
            try await waitUntil(playButton, is: .exists, .hittable)
            try await waitUntilValue(playButton, equals: "paused", timeout: .seconds(5))
        }

        #expect(playButton.value as? String == "paused", "Should start in paused state")

        // Background the app
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(1))

        // Trigger playback via deep link (same code path as intent)
        // The app's handleURL checks for "wxyc" scheme and calls play()
        let playURL = URL(string: "wxyc://play")!
        app.open(playURL)

        // Wait for app to activate and process the URL
        try await waitUntil(playButton, is: .exists, .hittable, timeout: .seconds(10))

        // Verify playback has started
        try await waitUntilValue(playButton, equals: "playing", timeout: .seconds(10))
        #expect(playButton.value as? String == "playing", "Playback should have started via deep link")

        // Clean up: stop playback
        playButton.tap()
        try await waitUntil(playButton, is: .exists, .hittable)
    }

    @Test("Deep link works while app is suspended")
    func deepLinkWorksWhileAppSuspended() async throws {
        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Ensure we're starting from a stopped state
        if playButton.value as? String == "playing" {
            playButton.tap()
            try await waitUntil(playButton, is: .exists, .hittable)
            try await waitUntilValue(playButton, equals: "paused", timeout: .seconds(5))
        }

        // Background the app and wait for suspension
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(3))

        // Trigger playback via deep link
        let playURL = URL(string: "wxyc://play")!
        app.open(playURL)

        try await waitUntil(playButton, is: .exists, .hittable, timeout: .seconds(10))

        // Verify playback started
        try await waitUntilValue(playButton, equals: "playing", timeout: .seconds(10))
        #expect(playButton.value as? String == "playing", "Deep link should start playback while app was suspended")

        // Clean up
        playButton.tap()
        try await waitUntil(playButton, is: .exists, .hittable)
    }

    // MARK: - Siri Intent Tests (Manual Verification Required)

    @Test(
        "PlayWXYC intent starts playback from background via Siri",
        .disabled("Siri automation unreliable in simulator - run manually on device")
    )
    func intentStartsPlaybackFromBackground() async throws {
        // Manual testing steps:
        //
        // 1. Launch WXYC app on a physical device with Siri enabled
        // 2. Verify app is not playing (play icon visible)
        // 3. Press Home button to background the app
        // 4. Activate Siri and say "Play WXYC"
        // 5. Wait for Siri to confirm ("Tuning in to WXYC...")
        // 6. Return to WXYC app
        // 7. Verify playback has started (pause icon visible)

        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        if playButton.value as? String == "playing" {
            playButton.tap()
            try await waitUntil(playButton, is: .exists, .hittable)
            try await waitUntilValue(playButton, equals: "paused", timeout: .seconds(5))
        }

        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(1))

        try XCUIDevice.shared.siriService.activate(voiceRecognitionText: "Play WXYC")
        try await Task.sleep(for: .seconds(3))

        app.activate()
        try await waitUntil(playButton, is: .exists, .hittable, timeout: .seconds(10))

        try await waitUntilValue(playButton, equals: "playing", timeout: .seconds(10))
        #expect(playButton.value as? String == "playing", "Playback should have started via intent")

        playButton.tap()
        try await waitUntil(playButton, is: .exists, .hittable)
    }

    // MARK: - Shortcuts Integration Tests

    @Test(
        "Trigger PlayWXYC from Shortcuts app",
        .disabled("Shortcuts app automation not available in standard UI tests")
    )
    func shortcutsIntegration() async throws {
        // Manual testing steps:
        //
        // 1. Create a Shortcut that runs the "Play WXYC" action
        // 2. Launch WXYC app and verify it's not playing
        // 3. Background the app
        // 4. Run the Shortcut from the Shortcuts app or widget
        // 5. Return to WXYC app
        // 6. Verify playback has started (pause icon visible)
    }

    // MARK: - Control Center Integration Tests

    @Test(
        "Trigger PlayWXYC from Control Center",
        .disabled("Control Center automation not available in standard UI tests")
    )
    func controlCenterIntegration() async throws {
        // Manual testing steps:
        //
        // 1. Add WXYC control to Control Center (Settings > Control Center)
        // 2. Launch WXYC app and verify it's not playing
        // 3. Background the app
        // 4. Open Control Center and tap the WXYC play control
        // 5. Return to WXYC app
        // 6. Verify playback has started (pause icon visible)
    }

    // MARK: - Playback State Accessibility Tests

    @Test("Playback button exposes playing state via accessibility value")
    func playbackButtonAccessibilityValue() async throws {
        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Check initial state has a value
        let initialValue = playButton.value as? String
        #expect(initialValue == "paused" || initialValue == "playing", "Button should have accessibility value")

        // Toggle and verify state changes
        let wasPlaying = initialValue == "playing"
        playButton.tap()
        try await waitUntil(playButton, is: .exists, .hittable)

        // Wait for state to change
        let expectedValue = wasPlaying ? "paused" : "playing"
        try await waitUntilValue(playButton, equals: expectedValue, timeout: .seconds(5))

        let newValue = playButton.value as? String
        #expect(newValue == expectedValue, "Accessibility value should reflect playback state")

        // Toggle back to restore state
        playButton.tap()
        try await waitUntil(playButton, is: .exists, .hittable)
    }
}

// MARK: - Value-Based Waiting

/// Waits until an element's accessibility value equals the expected value.
func waitUntilValue(
    _ element: XCUIElement,
    equals expectedValue: String,
    timeout: Duration = .seconds(5)
) async throws {
    try await waitUntil(timeout: timeout, "value equals '\(expectedValue)'") {
        element.value as? String == expectedValue
    }
}
