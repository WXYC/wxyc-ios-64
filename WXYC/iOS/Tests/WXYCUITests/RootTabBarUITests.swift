//
//  RootTabBarUITests.swift
//  WXYC
//
//  UI smoke for the R0 tab-bar migration (#489): the root shows a standard
//  tab bar instead of page dots, and both destinations are reachable by tap.
//  Tabs are selected by accessibility identifier (`tab.nowPlaying` / `tab.info`)
//  rather than element type, since the iOS 26 floating tab bar is not exposed
//  as XCUIElement.tabBars.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import XCTest

@Suite(
    "Root Tab Bar UI Tests",
    .serialized,
    .tags(.uiTest),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_UI"] == "1", "UI test — excluded from CI")
)
@MainActor
struct RootTabBarUITests {

    let app = XCUIApplication()

    init() {
        app.launch()
    }

    private var nowPlayingTab: XCUIElement { app.buttons["tab.nowPlaying"] }
    private var infoTab: XCUIElement { app.buttons["tab.info"] }

    // The app renders a Metal wallpaper and mesh-gradient animations
    // continuously, so XCUITest is slow to reach quiescence after a cold
    // launch. Gate readiness on the shallow, stable tab item (not a deep
    // content query) and allow generous timeouts.
    private let launchTimeout: Duration = .seconds(20)
    private let contentTimeout: Duration = .seconds(12)

    /// Waits until the tab bar is present so a first tap doesn't land before
    /// the cold-launched UI is interactive.
    private func waitForLaunch() async throws {
        try await waitUntil(nowPlayingTab, is: .exists, timeout: launchTimeout)
    }

    /// Taps a tab item by its center coordinate. The iOS 26 floating Liquid
    /// Glass tab bar reports its items as existing but not `isHittable` to
    /// XCUITest, so a normalized-coordinate tap is used instead of `tap()`,
    /// which would gate on hittability.
    private func tapTab(_ tab: XCUIElement) async throws {
        try await waitUntil(tab, is: .exists, timeout: launchTimeout)
        tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @Test("The root shows Now Playing and Info tab items")
    func tabItemsExist() async throws {
        try await waitUntil(nowPlayingTab, is: .exists, timeout: launchTimeout)
        try await waitUntil(infoTab, is: .exists, timeout: launchTimeout)
    }

    @Test("Tapping Info reaches the station page")
    func infoTabReachable() async throws {
        try await waitForLaunch()
        try await tapTab(infoTab)
        try await waitUntil(app.buttons["Make a request"], is: .exists, timeout: contentTimeout)
    }

    // A round-trip test (Info → back to Now Playing, asserting the playlist)
    // was tried and dropped: each extra query in the longer interaction gives
    // the continuously-animating Metal/visualizer UI another chance to be
    // mid-frame, which XCUITest can't snapshot, so it flaked on "matching
    // snapshots" timeouts unrelated to the tab logic. Directional reachability
    // is covered above; wallpaper-behind-the-bar visibility is covered by the
    // TabBarBackgroundClearer unit tests. This mirrors why these `.uiTest`
    // suites stay coarse and CI-excluded (WXYC_SKIP_UI=1).
}
