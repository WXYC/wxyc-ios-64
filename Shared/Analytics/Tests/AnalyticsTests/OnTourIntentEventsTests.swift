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

private extension ConcertIdentity {
    /// A stand-in show for the tests that are only about an event's own
    /// affordance key. The identity keys themselves are covered once, in
    /// `identityKeyNames`, and their agreement across events in
    /// `identityKeysMatchAcrossTier` — repeating them per event would just mean
    /// five tests failing together.
    static let fixture = ConcertIdentity(
        artist: "Jessica Pratt",
        artistId: 4821,
        venue: "Cat's Cradle",
        concertId: 991,
        status: "on_sale"
    )
}

@Suite("On Tour intent events")
struct OnTourIntentEventsTests {

    // MARK: - The shared identity payload

    // Every conforming event inherits these five keys through
    // `ConcertIntentEvent`, so they are tested once here rather than re-asserted
    // per event. Event names live in `EventNameStabilityTests`.

    @Test("The five shared keys use the names song_like_toggled uses")
    func identityKeyNames() {
        // These names are load-bearing: they must match SongLikeToggled's so a
        // liked-artist cohort joins against intent with no aliasing.
        let props = ConcertIdentity(
            artist: "Jessica Pratt",
            artistId: 4821,
            venue: "Cat's Cradle",
            concertId: 991,
            status: "on_sale"
        ).properties
        #expect(props["artist"] as? String == "Jessica Pratt")
        #expect(props["artist_id"] as? Int == 4821)
        #expect(props["venue"] as? String == "Cat's Cradle")
        #expect(props["concert_id"] as? Int == 991)
        #expect(props["status"] as? String == "on_sale")
        #expect(props.count == 5)
    }

    @Test("An unresolved headliner omits artist_id entirely")
    func omitsUnresolvedArtistID() {
        // Absent, not NSNull and not an Optional-wrapped Any — the trap that
        // forced SongLikeToggled to be hand-written rather than macro-derived.
        let props = ConcertIdentity(
            artist: "Some Local Opener",
            artistId: nil,
            venue: "Local 506",
            concertId: 12,
            status: "unknown"
        ).properties
        #expect(props["artist_id"] == nil)
        #expect(props.count == 4)
    }

    // MARK: - Affordance keys

    @Test(
        "Surface records which of the three ticket affordances was tapped",
        arguments: ["detail", "playcut_detail", "row"]
    )
    func surfaceValues(_ surface: String) throws {
        let event = ConcertTicketsTapped(concert: .fixture, surface: surface)
        let props = try #require(event.properties)
        #expect(props["surface"] as? String == surface)
    }

    // MARK: - Detail views

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

    // MARK: - Directions

    @Test(
        "Directions is its own event, not a ticket tap with a different surface",
        arguments: ["detail", "detail_map", "row"]
    )
    func directionsTappedSurfaces(_ surface: String) throws {
        // A separate name rather than an action property on the ticket event:
        // for a free show the CTA reads "RSVP" and directions is the truer
        // intent signal, and an affordance that dies is only visible as a dead
        // event name — hidden inside a healthy event's volume it looks like noise.
        let event = ConcertDirectionsTapped(concert: .fixture, surface: surface)
        let props = try #require(event.properties)
        #expect(props["surface"] as? String == surface)
    }

    // MARK: - Calendar

    @Test(
        "Every way the add-to-calendar flow can end is one event with an outcome",
        arguments: ["requested", "denied", "cancelled", "saved", "failed"]
    )
    func calendarFlowOutcomes(_ outcome: String) throws {
        // Replaces `concert_calendar_added`, which only ever fired on a save and
        // so could never show where the flow was losing people. A tap that ends
        // at the permission alert and a tap that ends at a saved event were
        // indistinguishable: both were simply absent.
        let event = ConcertCalendarFlow(
            concert: ConcertIdentity(
                artist: "Nilüfer Yanya",
                artistId: 1201,
                venue: "Local 506",
                concertId: 55,
                status: "on_sale"
            ),
            surface: "detail",
            outcome: outcome
        )
        let props = try #require(event.properties)
        #expect(props["outcome"] as? String == outcome)
        #expect(props["surface"] as? String == "detail")
        #expect(props["artist"] as? String == "Nilüfer Yanya")
        #expect(props["artist_id"] as? Int == 1201)
        #expect(props["concert_id"] as? Int == 55)
        #expect(props.count == 7)
    }

    @Test(
        "Surface covers the two in-app affordances and the Siri intent",
        arguments: ["detail", "row", "siri"]
    )
    func calendarFlowSurfaces(_ surface: String) throws {
        // Siri reports through the same event rather than one of its own: a
        // listener who adds a show by voice added a show, and splitting that
        // into a second name would make "how many shows get calendared" a sum
        // someone has to remember to write.
        let event = ConcertCalendarFlow(
            concert: ConcertIdentity(
                artist: "Duke Ellington & John Coltrane",
                artistId: 9,
                venue: "Motorco",
                concertId: 8,
                status: "on_sale"
            ),
            surface: surface,
            outcome: "saved"
        )
        let props = try #require(event.properties)
        #expect(props["surface"] as? String == surface)
    }

    // MARK: - Sharing

    @Test(
        "Sharing a show names the band being shared",
        arguments: ["detail", "row"]
    )
    func shareInitiatedCarriesBandIdentity(_ surface: String) throws {
        // Moved out of the browse tier: choosing to send a specific show to a
        // friend is the strongest intent signal on the tab, stronger than a
        // ticket tap, and the one most worth knowing per band. The *arrival*
        // event `concert_deep_link_opened` stays anonymous — the recipient
        // didn't choose the band, the sender did.
        let event = ConcertShareInitiated(concert: .fixture, surface: surface)
        let props = try #require(event.properties)
        #expect(props["surface"] as? String == surface)
        #expect(props["artist"] as? String == "Jessica Pratt")
    }

    // MARK: - Cross-event contract

    @Test("Every intent event agrees with the denominator on every shared key")
    func identityKeysMatchAcrossTier() throws {
        // The join is the whole reason this tier exists. Assert the events agree
        // rather than trusting the composition to stay in step as the tier
        // grows: this is the test that fails if a future event inlines its own
        // payload instead of composing ConcertIdentity, or spells one of the
        // five keys differently. Both of those are silent in production — the
        // query still runs, it just quietly misses half the rows.
        let identity = ConcertIdentity(
            artist: "Cat Power",
            artistId: 5,
            venue: "Haw River Ballroom",
            concertId: 42,
            status: "on_sale"
        )
        let shared = ["artist", "artist_id", "venue", "concert_id", "status"]
        let denominator = try #require(ConcertDetailViewed(concert: identity, source: "row").properties)

        // Each action, paired with the one key that names its own affordance.
        let actions: [(Set<String>, [String: Any])] = [
            (["surface"], try #require(ConcertTicketsTapped(concert: identity, surface: "detail").properties)),
            (["surface"], try #require(ConcertDirectionsTapped(concert: identity, surface: "detail").properties)),
            (["surface"], try #require(ConcertShareInitiated(concert: identity, surface: "detail").properties)),
            (
                ["surface", "outcome"],
                try #require(
                    ConcertCalendarFlow(concert: identity, surface: "detail", outcome: "saved").properties
                )
            ),
        ]

        #expect(Set(denominator.keys).subtracting(shared) == ["source"])
        for (ownKeys, props) in actions {
            for key in shared {
                #expect(String(describing: props[key]) == String(describing: denominator[key]))
            }
            #expect(Set(props.keys).subtracting(shared) == ownKeys)
        }
    }
}
