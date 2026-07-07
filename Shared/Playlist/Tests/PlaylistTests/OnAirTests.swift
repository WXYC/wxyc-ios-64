//
//  OnAirTests.swift
//  Playlist
//
//  Verifies the tri-state OnAir signal: its banner-title mapping (which decides
//  whether the on-air banner shows a name, "Auto DJ", or hides) and its Codable
//  round-trip, since OnAir is persisted as part of the cached Playlist.
//
//  Created by Jake Bromberg on 07/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("OnAir Tests")
struct OnAirTests {

    @Test("bannerTitle is the DJ name for .dj")
    func bannerTitleForDJ() {
        #expect(OnAir.dj("DJ MONSTER").bannerTitle == "DJ MONSTER")
    }

    @Test("bannerTitle is \"Auto DJ\" for .automation")
    func bannerTitleForAutomation() {
        #expect(OnAir.automation.bannerTitle == "Auto DJ")
    }

    @Test("bannerTitle is nil for .unknown so the banner hides")
    func bannerTitleForUnknown() {
        #expect(OnAir.unknown.bannerTitle == nil)
    }

    @Test(
        "Codable round-trips every state",
        arguments: [OnAir.dj("DJ HOUNDSTOOTH"), .automation, .unknown]
    )
    func codableRoundTrip(_ value: OnAir) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(OnAir.self, from: data)
        #expect(decoded == value)
    }
}
