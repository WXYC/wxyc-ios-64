//
//  OnTourTabUITests.swift
//  WXYC
//
//  UI smoke for the R1 On Tour tab (#490): the third tab is reachable and its
//  Filter button opens the filter sheet. Tabs are selected by accessibility
//  identifier (`tab.onTour`) via a normalized-coordinate tap, since the iOS 26
//  floating tab bar isn't exposed as `XCUIElement.tabBars` and reports items as
//  existing-but-not-hittable (same constraints as `RootTabBarUITests`).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import XCTest

@Suite(
    "On Tour Tab UI Tests",
    .serialized,
    .tags(.uiTest),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_UI"] == "1", "UI test — excluded from CI")
)
@MainActor
struct OnTourTabUITests {

    let app = XCUIApplication()

    init() {
        app.launch()
    }

    private var onTourTab: XCUIElement { app.buttons["tab.onTour"] }
    private var filterButton: XCUIElement { app.buttons["onTour.filterButton"] }

    private let launchTimeout: Duration = .seconds(20)
    private let contentTimeout: Duration = .seconds(12)

    /// Taps a tab item by its center coordinate — the floating Liquid Glass tab
    /// bar reports items as existing but not `isHittable`, so `tap()` (which
    /// gates on hittability) is avoided.
    private func tapTab(_ tab: XCUIElement) async throws {
        try await waitUntil(tab, is: .exists, timeout: launchTimeout)
        tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @Test("The root shows an On Tour tab item")
    func onTourTabExists() async throws {
        try await waitUntil(onTourTab, is: .exists, timeout: launchTimeout)
    }

    @Test("Tapping On Tour reaches the list and the Filter button opens the sheet")
    func filterSheetOpens() async throws {
        try await tapTab(onTourTab)
        // The Filter button is a normal (hittable) control in the tab header.
        try await waitUntil(filterButton, is: .exists, timeout: contentTimeout)
        filterButton.tap()
        try await waitUntil(app.navigationBars["Filters"], is: .exists, timeout: contentTimeout)
    }
}
