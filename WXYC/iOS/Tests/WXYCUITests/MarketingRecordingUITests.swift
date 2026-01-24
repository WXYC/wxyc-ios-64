//
//  MarketingRecordingUITests.swift
//  WXYC
//
//  UI automation for marketing video recording. Launches the app with -marketing
//  argument which triggers automatic playback and theme cycling via MarketingModeController.
//
//  Created by Claude on 01/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import XCTest

final class MarketingRecordingUITests: XCTestCase {

    /// Minimum duration to wait for the marketing sequence.
    /// The app's MarketingModeController:
    /// - Waits up to 10s for playlist to load
    /// - Holds for 2s on the playlist
    /// - Runs theme cycling for at least 15s
    /// Total: ~27+ seconds, we wait 35s to be safe
    private let recordingDuration: TimeInterval = 35

    // MARK: - Main Recording Sequence

    /// Launches the app in marketing mode and waits for the demo sequence to complete.
    ///
    /// When launched with `-marketing`, the app automatically:
    /// - Starts playback immediately
    /// - Waits for playlist to load
    /// - Holds 2 seconds on the playlist
    /// - Enters theme picker, navigates to random theme, exits
    /// - Waits 3 seconds
    /// - Repeats until at least 15 seconds have elapsed
    func testMarketingRecordingSequence() {
        let app = XCUIApplication()
        app.launchArguments = ["-marketing"]
        app.launch()

        // Wait for the app to appear
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App did not launch")

        // Wait for the marketing sequence to complete
        // The MarketingModeController runs for at least 15 seconds
        let expectation = XCTestExpectation(description: "Marketing sequence complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + recordingDuration) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: recordingDuration + 5)

        // Verify app is still running
        XCTAssertTrue(app.exists, "App should still be running after recording sequence")
    }
}
