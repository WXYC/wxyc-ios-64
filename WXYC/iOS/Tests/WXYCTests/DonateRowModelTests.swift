//
//  DonateRowModelTests.swift
//  WXYC
//
//  Tests for the visibility and URL-resolution rules behind the Station tab's
//  Donate row.
//
//  Created by Jake Bromberg on 08/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppServices
import Core
import Foundation
import Testing
import struct WXYCAPIModels.AppConfig
@testable import WXYC

@Suite("DonateRowModel")
struct DonateRowModelTests {

    // MARK: - Visibility

    @Test("hidden on the un-fetched defaults path — the dark-ship guarantee")
    func hiddenBeforeConfigArrives() {
        // Not a synthetic config: this is the literal `config()` returns on
        // every failure path, so the test fails if someone flips the default
        // without meaning to.
        let model = DonateRowModel(config: AppConfiguration.defaults)

        #expect(model.isVisible == false)
    }

    @Test("visible when a fetched config enables it")
    func visibleWhenFetchedTrue() {
        let model = DonateRowModel(config: .fetched(donateEnabled: true))

        #expect(model.isVisible == true)
    }

    @Test("hidden when a fetched config disables it")
    func hiddenWhenFetchedFalse() {
        let model = DonateRowModel(config: .fetched(donateEnabled: false))

        #expect(model.isVisible == false)
    }

    @Test("visible when a fetched config predates the field")
    func visibleWhenFetchedFieldAbsent() {
        // nil from a *fetched* response means the backend doesn't know about
        // the field yet — not "off". The compile-time fallback is a valid
        // destination, so the row is useful. The dark case is carried by
        // `defaults` pinning false, not by this branch.
        let model = DonateRowModel(config: .fetched(donateEnabled: nil))

        #expect(model.isVisible == true)
    }

    // MARK: - URL ladder

    @Test("a fetched donateUrl wins")
    func fetchedURLWins() {
        let model = DonateRowModel(
            config: .fetched(donateUrl: "https://example.littlegreenlight.com/lglforms/donate")
        )

        #expect(model.destination.absoluteString == "https://example.littlegreenlight.com/lglforms/donate")
    }

    @Test(
        "an unusable fetched donateUrl falls through to the compile-time fallback",
        arguments: [
            // What Backend-Service actually serves when DONATE_URL is unset on
            // Railway: `process.env.X || ''`, not null. URL(string: "") is nil.
            "",
            "   ",
            // Parses, but as a scheme-relative reference — SFSafariViewController
            // requires http/https and traps on anything else.
            "wxyc.org/donate",
            "mailto:donate@wxyc.org",
            "javascript:alert(1)",
            "not a url",
        ]
    )
    func unusableFetchedURLFallsThrough(donateUrl: String) {
        let model = DonateRowModel(config: .fetched(donateUrl: donateUrl))

        #expect(model.destination == RadioStation.WXYC.donateURL)
    }

    @Test("falls back to the compile-time URL when no config carries one")
    func fallsBackToCompileTimeURL() {
        let model = DonateRowModel(config: AppConfiguration.defaults)

        #expect(model.destination == RadioStation.WXYC.donateURL)
    }

    @Test("the compile-time fallback is a usable https destination")
    func compileTimeFallbackIsUsable() {
        // SFSafariViewController traps on a non-http(s) URL, and this rung has
        // no further fallback beneath it.
        #expect(RadioStation.WXYC.donateURL.scheme == "https")
    }
}

// MARK: - Fixtures

private extension AppConfig {
    /// A config shaped like a successful `/config` fetch, so tests read as
    /// "what the backend said" rather than as struct construction.
    static func fetched(
        donateUrl: String? = nil,
        donateEnabled: Bool? = nil
    ) -> AppConfig {
        AppConfig(
            posthogApiKey: "phc_remote",
            posthogHost: "https://remote.posthog.com",
            requestOMaticUrl: "https://remote.example.com/request",
            apiBaseUrl: "https://remote.api.wxyc.org",
            donateUrl: donateUrl,
            donateEnabled: donateEnabled
        )
    }
}
