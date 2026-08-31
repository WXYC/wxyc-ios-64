//
//  OnTourIntentEventsTests.swift
//  Analytics
//
//  Property-shape coverage for the On Tour *intent* tier — the events that
//  carry band identity because the listener chose a specific show. The browse
//  tier lives in `OnTourEventsTests.swift`, where the counts-only assertions
//  are what hold the privacy line.
//
//  These assertions guard the property *contract*, not privacy: `artist` and
//  `artist_id` must keep the exact key names `song_like_toggled` uses, because
//  the point of the tier is that a liked-artist cohort can be joined against
//  intent with no aliasing.
//
//  Created by Jake Bromberg on 08/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("On Tour intent events")
struct OnTourIntentEventsTests {

    // MARK: - Ticket taps

    @Test("Event name is the snake_cased type name")
    func eventName() {
        #expect(ConcertTicketsTapped.name == "concert_tickets_tapped")
    }

    @Test("Carries band identity under the same keys as song_like_toggled")
    func carriesBandIdentity() throws {
        let event = ConcertTicketsTapped(
            concert: ConcertIdentity(
                artist: "Jessica Pratt",
                artistId: 4821,
                venue: "Cat's Cradle",
                concertId: 991,
                status: "on_sale"
            ),
            surface: "detail"
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
            concert: ConcertIdentity(
                artist: "Some Local Opener",
                artistId: nil,
                venue: "Local 506",
                concertId: 12,
                status: "unknown"
            ),
            surface: "playcut_detail"
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
            concert: ConcertIdentity(
                artist: "Chuquimamani-Condori",
                artistId: 77,
                venue: "Nightlight",
                concertId: 3,
                status: "free"
            ),
            surface: surface
        )
        let props = try #require(event.properties)
        #expect(props["surface"] as? String == surface)
    }

    // MARK: - Detail views

    @Test("ConcertDetailViewed's name is the snake_cased type name")
    func detailViewedEventName() {
        #expect(ConcertDetailViewed.name == "concert_detail_viewed")
    }

    @Test("Detail views carry the same identity keys as the actions taken from them")
    func detailViewedCarriesBandIdentity() throws {
        // Every downstream On Tour action is a rate over this event, so its
        // identity keys have to be identical to the actions' — a band spelled
        // differently here than on concert_tickets_tapped can never have a
        // tap-through rate computed for it.
        let event = ConcertDetailViewed(
            concert: ConcertIdentity(
                artist: "Juana Molina",
                artistId: 4821,
                venue: "Cat's Cradle",
                concertId: 991,
                status: "on_sale"
            ),
            source: "row"
        )
        let props = try #require(event.properties)
        #expect(props["artist"] as? String == "Juana Molina")
        #expect(props["artist_id"] as? Int == 4821)
        #expect(props["venue"] as? String == "Cat's Cradle")
        #expect(props["concert_id"] as? Int == 991)
        #expect(props["source"] as? String == "row")
        #expect(props["status"] as? String == "on_sale")
        #expect(props.count == 6)
    }

    @Test("A detail view of an unresolved headliner omits artist_id entirely")
    func detailViewedOmitsUnresolvedArtistID() throws {
        let event = ConcertDetailViewed(
            concert: ConcertIdentity(
                artist: "Some Local Opener",
                artistId: nil,
                venue: "Local 506",
                concertId: 12,
                status: "unknown"
            ),
            source: "for_you"
        )
        let props = try #require(event.properties)
        #expect(props["artist_id"] == nil)
        #expect(props.count == 5)
    }

    @Test(
        "Source records which of the three arrival paths opened the detail",
        arguments: ["row", "for_you", "deep_link"]
    )
    func detailViewedSourceValues(_ source: String) throws {
        let event = ConcertDetailViewed(
            concert: ConcertIdentity(
                artist: "Stereolab",
                artistId: 77,
                venue: "Motorco",
                concertId: 3,
                status: "sold_out"
            ),
            source: source
        )
        let props = try #require(event.properties)
        #expect(props["source"] as? String == source)
    }

    // MARK: - Cross-event contract

    @Test("The denominator and the actions over it agree on every shared key")
    func identityKeysMatchAcrossTiers() throws {
        // The join is the whole reason this tier exists. Assert the two events
        // agree rather than trusting the composition to stay in step as the
        // tier grows: this is the test that fails if a future event inlines its
        // own payload instead of composing ConcertIdentity.
        let identity = ConcertIdentity(
            artist: "Cat Power",
            artistId: 5,
            venue: "Haw River Ballroom",
            concertId: 42,
            status: "on_sale"
        )
        let viewedProps = try #require(ConcertDetailViewed(concert: identity, source: "row").properties)
        let tappedProps = try #require(ConcertTicketsTapped(concert: identity, surface: "detail").properties)
        let shared = ["artist", "artist_id", "venue", "concert_id", "status"]
        for key in shared {
            #expect(String(describing: viewedProps[key]) == String(describing: tappedProps[key]))
        }
        // Beyond the shared keys, each event names its own affordance and
        // nothing else.
        #expect(Set(viewedProps.keys).subtracting(shared) == ["source"])
        #expect(Set(tappedProps.keys).subtracting(shared) == ["surface"])
    }
}
