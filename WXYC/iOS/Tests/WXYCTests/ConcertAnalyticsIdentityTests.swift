//
//  ConcertAnalyticsIdentityTests.swift
//  WXYC
//
//  Pins `Concert.analyticsIdentity`, the single mapping from a show to the keys
//  every On Tour intent event joins on. Every failure this guards is silent in
//  production: a wrong field here still produces a well-formed event, and the
//  PostHog query that then misses half its rows still runs and still returns a
//  number.
//
//  Created by Jake Bromberg on 08/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Concerts
import Foundation
import Testing
@testable import WXYC

@Suite("Concert.analyticsIdentity")
struct ConcertAnalyticsIdentityTests {

    /// Built from public initializers rather than the stub module, so the target
    /// needs only `Concerts` — the `UpcomingShowResolverTests` precedent.
    private func makeShow(
        id: Int = 4821,
        headliningArtistRaw: String = "Jessica Pratt",
        headliningArtistId: Int? = 512,
        title: String? = nil,
        status: ShowStatus = .onSale
    ) -> Concert {
        Concert(
            id: id,
            venue: Venue(id: 3, slug: "cats-cradle", name: "Cat's Cradle", city: "Carrboro", state: "NC"),
            startsOn: Date(timeIntervalSince1970: 1_785_898_800),
            headliningArtistRaw: headliningArtistRaw,
            headliningArtistId: headliningArtistId,
            title: title,
            status: status
        )
    }

    @Test("Maps the five join keys off the show")
    func mapsTheJoinKeys() throws {
        let props = try #require(makeShow().analyticsIdentity.properties as [String: Any]?)
        #expect(props["artist"] as? String == "Jessica Pratt")
        #expect(props["artist_id"] as? Int == 512)
        #expect(props["venue"] as? String == "Cat's Cradle")
        #expect(props["concert_id"] as? Int == 4821)
        #expect(props["status"] as? String == "on_sale")
    }

    @Test("A titled show still reports the band, never the billed title")
    func titledShowReportsTheBandNotTheTitle() {
        // The bug this suite exists for. `headlineName` is `title ?? raw` — a
        // display string — while `headliningArtistId` is always resolved from
        // `headliningArtistRaw`. Pairing them ships the festival's name beside
        // the headliner's catalog id: one id under two names across events, so
        // `GROUP BY artist` splits the band and the join to
        // `song_like_toggled.artist` drops every titled show entirely.
        let festival = makeShow(title: "Hopscotch Music Festival")

        #expect(festival.headlineName == "Hopscotch Music Festival")
        #expect(festival.analyticsIdentity.artist == "Jessica Pratt")
        #expect(festival.analyticsIdentity.artistId == 512)
    }

    @Test("The artist name and id always describe the same entity")
    func nameAndIDAgree() {
        // Stated as its own assertion because it is the invariant, not the
        // example: whatever `artist` is, it is the string `artistId` was
        // resolved from.
        for title in [nil, "Hopscotch Music Festival", "A Benefit for WXYC"] {
            let show = makeShow(title: title)
            #expect(show.analyticsIdentity.artist == show.headliningArtistRaw)
        }
    }

    @Test("An unresolved headliner keeps a nil id rather than guessing one")
    func unresolvedHeadlinerHasNoID() {
        let show = makeShow(headliningArtistRaw: "Some Local Opener", headliningArtistId: nil)
        #expect(show.analyticsIdentity.artistId == nil)
        #expect(show.analyticsIdentity.properties["artist_id"] == nil)
    }

    @Test("Status travels as the ShowStatus raw value the dashboards filter on")
    func statusIsTheRawValue() {
        #expect(makeShow(status: .soldOut).analyticsIdentity.status == "sold_out")
        #expect(makeShow(status: .cancelled).analyticsIdentity.status == "cancelled")
        #expect(makeShow(status: .free).analyticsIdentity.status == "free")
    }
}
