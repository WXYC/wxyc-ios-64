//
//  PlaybackButtonObservationUITests.swift
//  WXYC
//
//  UI Integration tests for PlaybackButton observation behavior
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import XCTest

@Suite(
    "PlaybackButton UI Integration Tests",
    .serialized,
    .tags(.slow),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_SLOW"] == "1", "Slow test — excluded from CI")
)
@MainActor
struct PlaybackButtonObservationUITests {

    let app = XCUIApplication()

    init() {
        app.launch()
    }

    @Test("State survives backgrounding")
    func stateSurvivesBackgrounding() async throws {
        let playButton = app.buttons["playPauseButton"]

        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Start playback
        playButton.tap()
        try await waitUntil(playButton, is: .exists, .hittable)

        // Background the app
        XCUIDevice.shared.press(.home)

        // Wait for app to enter background (need real time for OS transition)
        try await Task.sleep(for: .seconds(1))

        // Foreground the app
        app.activate()

        // Wait for button to be accessible again
        try await waitUntil(playButton, is: .exists, .hittable, timeout: .seconds(10))

        // Button should still exist and be responsive
        #expect(playButton.exists, "Button should exist after foregrounding")
        #expect(playButton.isHittable, "Button should be hittable after foregrounding")

        // Verify button still responds
        playButton.tap()
        try await waitUntil(playButton, is: .exists)
        #expect(playButton.exists, "Button should respond after backgrounding cycle")
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
