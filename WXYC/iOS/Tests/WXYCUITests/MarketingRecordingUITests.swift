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

    /// Wall-clock the marketing sequence needs, worst case, before the recording
    /// can be stopped. The app's `MarketingModeController`:
    /// - Waits up to 10s for playlist to load
    /// - Holds for 2s on the playlist
    /// - Cycles themes for at least 6s
    /// - Likes the on-air track, holds 3s
    /// - Routes to On Tour (2s), opens a concert detail (4s)
    /// - Routes to Liked (3s), then Station (2s)
    /// Total: ~32s worst case; we wait 55s to leave headroom for simulator/CI
    /// timing drift, since `record-marketing.sh`'s `EXIT` trap stops the
    /// recording the instant this test returns — cutting the wait short would
    /// truncate the last scene(s).
    private let recordingDuration: TimeInterval = 55

    // MARK: - Main Recording Sequence

    /// Launches the app in marketing mode and waits for the demo sequence to
    /// complete. This is the test `record-marketing.sh` runs to drive the
    /// capture, so it stays lenient by design (D1): it asserts only that the
    /// app survived the full wait, never per-scene navigation, so a
    /// slightly-drifted take is still captured and processed rather than
    /// silently discarded. Per-scene correctness is covered separately by
    /// ``testMarketingSequenceVisitsAllTabs()``, which is not in
    /// `record-marketing.sh`'s `-only-testing:` filter and so never risks a
    /// capture.
    ///
    /// When launched with `-marketing`, the app automatically:
    /// - Starts playback, waits for the playlist, holds 2s
    /// - Cycles wallpaper themes for at least 6s
    /// - Likes the on-air track (heart-burst celebration)
    /// - Visits On Tour (list + For You shelf, then a concert detail), Liked,
    ///   and Station in turn
    func testMarketingRecordingSequence() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["WXYC_SKIP_UI"] == "1",
            "UI test — excluded from CI"
        )
        let app = XCUIApplication()
        app.launchArguments = ["-marketing"]
        app.launch()

        // Wait for the app to appear
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App did not launch")

        // Hold for the full recording window. A never-fulfilled expectation
        // always times out after exactly `recordingDuration`, unlike
        // `app.wait(for: .runningForeground, timeout:)` — the app is already
        // foregrounded, so that call would return in milliseconds, the test
        // would exit, and record-marketing.sh's `EXIT` trap would stop the
        // recording almost immediately, truncating it to a fraction of a
        // second. GCD's `DispatchQueue.main.asyncAfter` is banned in this repo
        // (docs/swift-style.md); `XCTWaiter` is the sanctioned hold.
        let hold = XCTestExpectation(description: "Hold while the marketing sequence records")
        _ = XCTWaiter.wait(for: [hold], timeout: recordingDuration)

        // Verify app is still running
        XCTAssertTrue(app.exists, "App should still be running after recording sequence")
    }

    // MARK: - Strict tab-visit verification

    /// Verifies the `-marketing` sequence actually reaches every tab, so a
    /// route-driving regression is caught even though ``testMarketingRecordingSequence()``
    /// stays lenient (D1). Not in `record-marketing.sh`'s `-only-testing:`
    /// filter, so a failure here never costs a capture.
    func testMarketingSequenceVisitsAllTabs() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["WXYC_SKIP_UI"] == "1",
            "UI test — excluded from CI"
        )
        let app = XCUIApplication()
        app.launchArguments = ["-marketing"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App did not launch")

        // The sequence spends its first ~15-20s on playback + theme cycling
        // before routing to On Tour. Timeouts here are deliberately generous —
        // manual verification (direct `simctl launch`, no XCUITest instrumentation)
        // shows the full sequence lands On Tour → Liked → Station inside ~20s, but
        // XCUITest's own accessibility-tree polling measurably slows the app down
        // (and this test isn't in record-marketing.sh's -only-testing: filter, so
        // there's no capture-window cost to erring generous — D1).
        XCTAssertTrue(
            app.otherElements["onTourView"].waitForExistence(timeout: 45),
            "Marketing sequence never reached On Tour"
        )
        XCTAssertTrue(
            app.otherElements["likedTabView"].waitForExistence(timeout: 20),
            "Marketing sequence never reached Liked"
        )
        XCTAssertTrue(
            app.otherElements["stationView"].waitForExistence(timeout: 20),
            "Marketing sequence never reached Station"
        )
    }
}
