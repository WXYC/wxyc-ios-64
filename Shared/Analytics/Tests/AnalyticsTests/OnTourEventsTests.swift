//
//  OnTourEventsTests.swift
//  Analytics
//
//  Property-shape coverage for the On Tour For You shelf events. The
//  shelf-impression event carries a per-tier card count — loved, similar, and
//  (as of #551) station — so the analytics can tell the cold-start station tier
//  apart from the personal tiers. These are counts only: no concert or artist
//  identity, per the On Tour privacy invariant.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("On Tour For You events")
struct OnTourEventsTests {

    @Test("ForYouShelfImpression carries all three tier counts")
    func shelfImpressionTierCounts() throws {
        let event = ForYouShelfImpression(lovedCount: 2, similarCount: 3, stationCount: 4)
        let props = try #require(event.properties)
        #expect(props["loved_count"] as? Int == 2)
        #expect(props["similar_count"] as? Int == 3)
        #expect(props["station_count"] as? Int == 4)
    }

    @Test("ForYouCardTapped records the station tier name")
    func cardTappedStationTier() throws {
        // The station tier's analytics name is the third recommendation kind; a
        // tapped station card must report it distinctly, not collapse into
        // "similar".
        let event = ForYouCardTapped(tier: "station")
        let props = try #require(event.properties)
        #expect(props["tier"] as? String == "station")
    }
}
