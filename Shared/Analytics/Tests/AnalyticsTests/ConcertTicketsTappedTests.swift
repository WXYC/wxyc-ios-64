//
//  ConcertTicketsTappedTests.swift
//  Analytics
//
//  Property-shape coverage for ``ConcertTicketsTapped``, the first On Tour
//  event that carries band identity. These assertions guard the property
//  *contract*, not privacy: `artist` and `artist_id` must keep the exact key
//  names `song_like_toggled` uses, because the point of the event is that a
//  liked-artist cohort can be joined against ticket taps with no aliasing.
//
//  Created by Jake Bromberg on 08/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("On Tour ticket interaction events")
struct ConcertTicketsTappedTests {

    @Test("Event name is the snake_cased type name")
    func eventName() {
        #expect(ConcertTicketsTapped.name == "concert_tickets_tapped")
    }

    @Test("Carries band identity under the same keys as song_like_toggled")
    func carriesBandIdentity() throws {
        let event = ConcertTicketsTapped(
            artist: "Jessica Pratt",
            artistId: 4821,
            venue: "Cat's Cradle",
            concertId: 991,
            surface: "detail",
            status: "on_sale"
        )
        let props = try #require(event.properties)
        // These two key names are load-bearing: they must match
        // SongLikeToggled's so a join needs no aliasing.
        #expect(props["artist"] as? String == "Jessica Pratt")
        #expect(props["artist_id"] as? Int == 4821)
        #expect(props["venue"] as? String == "Cat's Cradle")
        #expect(props["concert_id"] as? Int == 991)
        #expect(props["surface"] as? String == "detail")
        #expect(props["status"] as? String == "on_sale")
        #expect(props.count == 6)
    }

    @Test("Omits artist_id entirely when the headliner is unresolved")
    func omitsUnresolvedArtistID() throws {
        // An unresolved headliner must be absent, not NSNull or an
        // Optional-wrapped Any — the trap that forced SongLikeToggled to be
        // hand-written rather than macro-derived.
        let event = ConcertTicketsTapped(
            artist: "Some Local Opener",
            artistId: nil,
            venue: "Local 506",
            concertId: 12,
            surface: "playcut_detail",
            status: "unknown"
        )
        let props = try #require(event.properties)
        #expect(props["artist_id"] == nil)
        #expect(props.count == 5)
    }

    @Test(
        "Surface records which of the three ticket affordances was tapped",
        arguments: ["detail", "playcut_detail", "row"]
    )
    func surfaceValues(_ surface: String) throws {
        let event = ConcertTicketsTapped(
            artist: "Chuquimamani-Condori",
            artistId: 77,
            venue: "Nightlight",
            concertId: 3,
            surface: surface,
            status: "free"
        )
        let props = try #require(event.properties)
        #expect(props["surface"] as? String == surface)
    }
}
