//
//  OnTourEventsTests.swift
//  Analytics
//
//  Property-shape coverage for the On Tour "Heard on WXYC" shelf events. The
//  shelf-impression event carries a per-tier card count — loved and station — so
//  the analytics can tell the cold-start station tier apart from the personal
//  loved tier. These are counts only: no concert or artist identity, per the On
//  Tour privacy invariant.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("On Tour For You events")
struct OnTourEventsTests {

    @Test("ForYouShelfImpression carries the loved and station tier counts, nothing else")
    func shelfImpressionTierCounts() throws {
        let event = ForYouShelfImpression(lovedCount: 2, stationCount: 4)
        let props = try #require(event.properties)
        #expect(props["loved_count"] as? Int == 2)
        #expect(props["station_count"] as? Int == 4)
        // The similar tier is gone — no `similar_count` rides along.
        #expect(props.count == 2)
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

    @Test("ForYouCardDismissed records the tier name")
    func cardDismissedTier() throws {
        // "Not interested" carries the recommendation kind only — never the concert
        // or the liked artist that surfaced it.
        let event = ForYouCardDismissed(tier: "loved")
        let props = try #require(event.properties)
        #expect(props["tier"] as? String == "loved")
    }

    @Test("ConcertShareInitiated records only the surface", arguments: ["detail", "row"])
    func concertShareInitiatedSurface(_ surface: String) throws {
        // A share carries the originating surface ("detail" chrome button vs. "row"
        // context menu) and nothing else — never the concert id or artist, per the
        // On Tour privacy invariant. The link itself resolves the show server-side.
        let event = ConcertShareInitiated(surface: surface)
        let props = try #require(event.properties)
        #expect(props["surface"] as? String == surface)
        #expect(props.count == 1)
    }

    @Test(
        "ConcertDeepLinkOpened records the link source and resolution rung, nothing else",
        arguments: [
            ("universalLink", "window"),
            ("universalLink", "byID"),
            ("scheme", "missed"),
        ]
    )
    func concertDeepLinkOpened(_ pair: (source: String, resolution: String)) throws {
        // The arrival event carries which link form opened the app and which rung
        // of the resolution ladder resolved it — both low-cardinality labels. It
        // never carries the concert id: a shared link is public, but which show a
        // listener opened is taste data that stays on the device.
        let event = ConcertDeepLinkOpened(source: pair.source, resolution: pair.resolution)
        let props = try #require(event.properties)
        #expect(props["source"] as? String == pair.source)
        #expect(props["resolution"] as? String == pair.resolution)
        #expect(props.count == 2)
    }

    @Test(
        "ConcertCalendarAdded records surface and timing shape, nothing else",
        arguments: [
            ("detail", "timed"),
            ("row", "allDay"),
        ]
    )
    func concertCalendarAdded(_ pair: (surface: String, timing: String)) throws {
        // A committed calendar add carries the originating surface and the event
        // shape ("timed" vs. "allDay") — both low-cardinality labels. It never
        // carries the concert, artist, or any calendar identity, per the On Tour
        // privacy invariant.
        let event = ConcertCalendarAdded(surface: pair.surface, timing: pair.timing)
        let props = try #require(event.properties)
        #expect(props["surface"] as? String == pair.surface)
        #expect(props["timing"] as? String == pair.timing)
        #expect(props.count == 2)
    }
}
