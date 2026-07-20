//
//  OnTourTabUITests.swift
//  WXYC
//
//  UI smoke for the R1 On Tour tab (#490): the third tab is reachable, its
//  Filter button opens the filter sheet, and a For You card can be dismissed via
//  its overflow menu. Tabs are selected by accessibility identifier (`tab.onTour`)
//  via a normalized-coordinate tap, since the iOS 26 floating tab bar isn't
//  exposed as `XCUIElement.tabBars` and reports items as existing-but-not-hittable
//  (same constraints as `RootTabBarUITests`).
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
        // Reset the persisted dismissed-shows set so the For You dismiss test
        // starts from a clean shelf; harmless for the other cases.
        app.launchArguments = ["-uiTestResetForYou"]
        app.launch()
    }

    private var onTourTab: XCUIElement { app.buttons["tab.onTour"] }
    private var filterButton: XCUIElement { app.buttons["onTour.filterButton"] }

    /// The first For You card (its poster button), matched by the `forYouCard.<id>`
    /// identifier prefix while excluding the sibling `.overflow` control.
    private var firstForYouCard: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'forYouCard.' AND NOT (identifier ENDSWITH '.overflow')")
        ).firstMatch
    }

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

    @Test("Dismissing a For You card via its overflow menu removes it from the shelf")
    func dismissForYouCardViaOverflow() async throws {
        try await tapTab(onTourTab)

        // The For You shelf renders only when the on-device match produced a card.
        // A DEBUG build seeds a loved card from the fetched window, so given a
        // non-empty live concert window at least one card appears. Environment-
        // gated like the rest of this suite (WXYC_SKIP_UI excludes it from CI).
        try await waitUntil(firstForYouCard, is: .exists, timeout: contentTimeout)
        let cardID = firstForYouCard.identifier

        // The overflow ••• is a sibling above the card in the ZStack, so its tap
        // isn't swallowed by the card's own navigation button.
        let overflow = app.descendants(matching: .any)
            .matching(identifier: "\(cardID).overflow").firstMatch
        try await waitUntil(overflow, is: .exists, .hittable, timeout: contentTimeout)
        overflow.tap()

        let notInterested = app.buttons["Not interested"]
        try await waitUntil(notInterested, is: .exists, timeout: contentTimeout)
        notInterested.tap()

        // The dismissed card leaves the shelf: `recommendations(for:)` reads the
        // store's observed `ids`, so the @Observable change repaints without it.
        let dismissedCard = app.descendants(matching: .any)
            .matching(identifier: cardID).firstMatch
        try await waitUntil(timeout: contentTimeout, "card \(cardID) removed") { !dismissedCard.exists }
    }
}
