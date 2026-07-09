//
//  UpcomingShowTests.swift
//  Playlist
//
//  Decode + intrinsic-accessor tests for the touring-show model. The wire shape
//  mirrors triangle-shows' `EventResponse` (see WXYC/triangle-shows backend/app/schemas.py).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Playlist

@Suite("UpcomingShow")
struct UpcomingShowTests {

    /// A realistic full-detail event payload (Jessica Pratt at Cat's Cradle),
    /// using a WXYC-canonical touring artist.
    private static let fullJSON = """
    {
        "id": 4821,
        "venue_id": 3,
        "name": "Jessica Pratt",
        "artist": "Jessica Pratt",
        "support_artists": "Julie Byrne",
        "date": "2026-08-01",
        "doors_time": "19:00:00",
        "show_time": "20:00:00",
        "ticket_url": "https://www.etix.com/ticket/p/jessica-pratt",
        "source_url": "https://catscradle.com/event/jessica-pratt",
        "price_min": 22.0,
        "price_max": 25.0,
        "image_url": "https://img.example/jessica-pratt.jpg",
        "genre": "Rock",
        "subgenre": "Folk",
        "status": "on_sale",
        "age_restriction": "All Ages",
        "description": "An evening with Jessica Pratt.",
        "source": "squarespace",
        "venue_name": "Cat's Cradle",
        "venue_city": "Carrboro",
        "venue_color": "#B34876"
    }
    """

    // MARK: - Full decode

    @Test("Decodes a full event payload")
    func decodesFullPayload() throws {
        let show = try JSONDecoder().decode(UpcomingShow.self, from: Data(Self.fullJSON.utf8))

        #expect(show.id == 4821)
        #expect(show.eventName == "Jessica Pratt")
        #expect(show.artist == "Jessica Pratt")
        #expect(show.supportArtists == "Julie Byrne")
        #expect(show.venueName == "Cat's Cradle")
        #expect(show.venueCity == "Carrboro")
        #expect(show.status == .onSale)
        #expect(show.priceMin == 22.0)
        #expect(show.priceMax == 25.0)
        #expect(show.doorsTime == "19:00:00")
        #expect(show.showTime == "20:00:00")
        #expect(show.ticketURL == URL(string: "https://www.etix.com/ticket/p/jessica-pratt"))
        #expect(show.sourceURL == URL(string: "https://catscradle.com/event/jessica-pratt"))
        #expect(show.imageURL == URL(string: "https://img.example/jessica-pratt.jpg"))
        #expect(show.ageRestriction == "All Ages")
    }

    @Test("Parses the date as a calendar day in the station's time zone")
    func parsesDateInStationZone() throws {
        let show = try JSONDecoder().decode(UpcomingShow.self, from: Data(Self.fullJSON.utf8))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        let components = calendar.dateComponents([.year, .month, .day], from: show.date)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 1)
    }

    // MARK: - Minimal / degraded decode

    @Test("Decodes a minimal payload, leaving optionals nil")
    func decodesMinimalPayload() throws {
        let json = """
        {
            "id": 12,
            "venue_id": 1,
            "name": "Chuquimamani-Condori",
            "date": "2026-09-15",
            "status": "free",
            "source": "webflow_cms"
        }
        """
        let show = try JSONDecoder().decode(UpcomingShow.self, from: Data(json.utf8))

        #expect(show.id == 12)
        #expect(show.eventName == "Chuquimamani-Condori")
        #expect(show.status == .free)
        #expect(show.artist == nil)
        #expect(show.supportArtists == nil)
        #expect(show.venueName == nil)
        #expect(show.venueCity == nil)
        #expect(show.doorsTime == nil)
        #expect(show.showTime == nil)
        #expect(show.priceMin == nil)
        #expect(show.priceMax == nil)
        #expect(show.ticketURL == nil)
        #expect(show.sourceURL == nil)
        #expect(show.imageURL == nil)
        #expect(show.ageRestriction == nil)
    }

    @Test("Decodes an unrecognized status as .unknown without throwing")
    func decodesUnknownStatus() throws {
        let json = """
        { "id": 1, "venue_id": 1, "name": "Juana Molina", "date": "2026-08-20", "status": "postponed", "source": "tribe_events" }
        """
        let show = try JSONDecoder().decode(UpcomingShow.self, from: Data(json.utf8))
        #expect(show.status == .unknown)
    }

    // MARK: - ctaURL (intrinsic data selection)

    @Test("ctaURL prefers the venue source_url over ticket_url")
    func ctaURLPrefersSourceURL() {
        let show = UpcomingShow.stub(
            ticketURL: URL(string: "https://etix.com/x"),
            sourceURL: URL(string: "https://catscradle.com/event/x")
        )
        #expect(show.ctaURL == URL(string: "https://catscradle.com/event/x"))
    }

    @Test("ctaURL falls back to ticket_url when source_url is absent")
    func ctaURLFallsBackToTicketURL() {
        let show = UpcomingShow.stub(
            ticketURL: URL(string: "https://etix.com/x"),
            sourceURL: nil
        )
        #expect(show.ctaURL == URL(string: "https://etix.com/x"))
    }

    @Test("ctaURL is nil when neither URL is present")
    func ctaURLNilWhenNoURLs() {
        let show = UpcomingShow.stub(ticketURL: nil, sourceURL: nil)
        #expect(show.ctaURL == nil)
    }
}
