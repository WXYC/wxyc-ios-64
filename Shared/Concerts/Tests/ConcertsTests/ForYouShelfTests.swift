//
//  ForYouShelfTests.swift
//  Concerts
//
//  Coverage for the on-device "Heard on WXYC" recommendation engine
//  (WXYC/wxyc-ios-64#493): loved / station tiering, loved-then-station ordering,
//  the injected station-tier cap, and dismissal. The engine is pure — no likes
//  store, no flag provider, no clock — so the cap arrives as a parameter and
//  likes arrive as plain fixtures (WXYC-canonical artists).
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

@Suite("ForYouShelf")
struct ForYouShelfTests {

    // MARK: - Fixtures

    // WXYC-canonical liked artists with fixed catalog ids.
    private let stereolab = LikedArtist(id: 41, name: "Stereolab")
    private let catPower = LikedArtist(id: 88, name: "Cat Power")

    /// A concert on `Concert.defaultStartsOn` offset by `offset` days, for
    /// ordering assertions.
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Concert.defaultStartsOn) ?? Concert.defaultStartsOn
    }

    // MARK: - Similar signal is ignored (tier removed)

    @Test("A liked affinity-neighbor no longer surfaces a card")
    func similarNeighborDoesNotSurface() {
        // Headliner (Jessica Pratt, 512) is unliked; liked Stereolab (41) is a
        // strong affinity neighbor. The shelf used to promote this as a "similar"
        // card; the tier is now cut, so the affinity signal surfaces nothing — even
        // with the station tier turned on, since the show is not station-recommended.
        let concert = Concert.stub(id: 2, headliningArtistRaw: "Jessica Pratt", headliningArtistId: 512,
                                   similarArtists: [SimilarArtist(artistId: 41, weight: 0.9)])
        #expect(ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab]).isEmpty)
        #expect(ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab], stationCap: 5).isEmpty)
    }

    // MARK: - Cold start

    @Test("No likes and no station cap yields an empty shelf")
    func coldStartLikesOnly() {
        // Cold start with the station tier off (default cap 0) and a concert that
        // is not station-recommended: nothing to surface. The station tier's
        // cold-start fill is covered by the Station recommended section below.
        let concert = Concert.stub(id: 1, headliningArtistId: 41)
        #expect(ForYouShelf.recommendations(concerts: [concert], likedArtists: []).isEmpty)
    }

    // MARK: - Loved tier

    @Test("A liked headliner surfaces a loved card")
    func lovedCard() {
        let concert = Concert.stub(id: 1, headliningArtistRaw: "Stereolab", headliningArtistId: 41)
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab])
        #expect(shelf.count == 1)
        #expect(shelf[0].concert.id == 1)
        #expect(shelf[0].tier == .loved)
    }

    @Test("Loved cards preserve the input window order")
    func lovedPreservesOrder() {
        let a = Concert.stub(id: 60, startsOn: day(0), headliningArtistId: 41)
        let b = Concert.stub(id: 61, startsOn: day(1), headliningArtistId: 88)
        let shelf = ForYouShelf.recommendations(concerts: [a, b], likedArtists: [catPower, stereolab])
        #expect(shelf.map(\.concert.id) == [60, 61])
    }

    @Test("A concert with an unliked headliner and no station signal yields no card")
    func noMatchNoCard() {
        let concert = Concert.stub(id: 50, headliningArtistId: 999,
                                   similarArtists: [SimilarArtist(artistId: 777, weight: 0.9)])
        #expect(ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab]).isEmpty)
    }

    // MARK: - Tier precedence & de-duplication

    @Test("Loved cards sort before station cards")
    func lovedBeforeStation() {
        let station = Concert.stub(id: 3, headliningArtistId: 700, stationRecommended: true)
        let loved = Concert.stub(id: 11, headliningArtistId: 41, stationRecommended: false)
        let shelf = ForYouShelf.recommendations(
            concerts: [station, loved], likedArtists: [stereolab], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [11, 3])
        #expect(shelf[0].tier == .loved)
        #expect(shelf[1].tier == .stationRecommended)
    }

    @Test("A concert that qualifies as both loved and station appears once, as loved")
    func stationDedupWithLoved() {
        let concert = Concert.stub(id: 6, headliningArtistId: 41, stationRecommended: true)
        let shelf = ForYouShelf.recommendations(
            concerts: [concert], likedArtists: [stereolab], stationCap: 5)
        #expect(shelf.count == 1)
        #expect(shelf[0].tier == .loved)
    }

    // MARK: - Station recommended (#577, cold-start tier)

    @Test("Cold start (zero likes) surfaces station cards, soonest first")
    func coldStartStationCards() {
        // No likes at all — the case the station tier exists to fill. There is no
        // scalar to rank on, so the soonest recommended show leads.
        let deerhoof = Concert.stub(id: 100, startsOn: day(2), headliningArtistRaw: "Deerhoof",
                                    headliningArtistId: 201, stationRecommended: true)
        let rem = Concert.stub(id: 101, startsOn: day(0), headliningArtistRaw: "R.E.M.",
                               headliningArtistId: 202, stationRecommended: true)
        let luna = Concert.stub(id: 102, startsOn: day(1), headliningArtistRaw: "Luna",
                                headliningArtistId: 203, stationRecommended: true)
        let shelf = ForYouShelf.recommendations(
            concerts: [deerhoof, rem, luna], likedArtists: [], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [101, 102, 100])
        #expect(shelf.allSatisfy { $0.tier == .stationRecommended })
    }

    @Test("Station cards order by concert date ascending, not input order")
    func stationOrderedByDateAscending() {
        let later = Concert.stub(id: 20, startsOn: day(2), headliningArtistId: 901, stationRecommended: true)
        let sooner = Concert.stub(id: 21, startsOn: day(1), headliningArtistId: 902, stationRecommended: true)
        let shelf = ForYouShelf.recommendations(
            concerts: [later, sooner], likedArtists: [], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [21, 20])
    }

    @Test("Same-day station cards tie-break by concert id ascending")
    func stationTieBreaksByID() {
        let higherID = Concert.stub(id: 23, startsOn: day(1), headliningArtistId: 901, stationRecommended: true)
        let lowerID = Concert.stub(id: 22, startsOn: day(1), headliningArtistId: 902, stationRecommended: true)
        let shelf = ForYouShelf.recommendations(
            concerts: [higherID, lowerID], likedArtists: [], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [22, 23])
    }

    @Test("The station tier is capped to `stationCap`, keeping the soonest shows")
    func stationCapEnforced() {
        let s1 = Concert.stub(id: 10, startsOn: day(2), headliningArtistId: 901, stationRecommended: true)
        let s2 = Concert.stub(id: 11, startsOn: day(0), headliningArtistId: 902, stationRecommended: true)
        let s3 = Concert.stub(id: 12, startsOn: day(1), headliningArtistId: 903, stationRecommended: true)
        let shelf = ForYouShelf.recommendations(
            concerts: [s1, s2, s3], likedArtists: [], stationCap: 2)
        #expect(shelf.map(\.concert.id) == [11, 12])
    }

    @Test("No station cards when no concert is station-recommended")
    func noStationWhenNoneRecommended() {
        // Every concert says false (explicitly or by default) → an empty shelf,
        // even with the tier turned on.
        let explicitFalse = Concert.stub(id: 13, headliningArtistId: 901, stationRecommended: false)
        let defaultFalse = Concert.stub(id: 14, headliningArtistId: 902)
        let shelf = ForYouShelf.recommendations(
            concerts: [explicitFalse, defaultFalse], likedArtists: [], stationCap: 5)
        #expect(shelf.isEmpty)
    }

    @Test("The station tier is off by default (stationCap defaults to 0)")
    func stationOffByDefault() {
        // The engine default keeps the likes-only shelf: a caller must opt in with
        // a positive stationCap to turn the tier on.
        let concert = Concert.stub(id: 30, headliningArtistId: 901, stationRecommended: true)
        #expect(ForYouShelf.recommendations(concerts: [concert], likedArtists: []).isEmpty)
    }

    // MARK: - Tier counts (#551, shelf-impression analytics)

    @Test("Tier counts bucket every card by its own tier")
    func tierCountsBucketByTier() {
        let recommendations = [
            ForYouRecommendation(concert: .stub(id: 1), tier: .loved),
            ForYouRecommendation(concert: .stub(id: 2), tier: .loved),
            ForYouRecommendation(concert: .stub(id: 4), tier: .stationRecommended),
        ]
        #expect(recommendations.tierCounts == ForYouTierCounts(loved: 2, stationRecommended: 1))
    }

    @Test("An empty shelf has zero cards in every tier")
    func tierCountsEmpty() {
        #expect([ForYouRecommendation]().tierCounts == ForYouTierCounts(loved: 0, stationRecommended: 0))
    }

    // MARK: - Dismissed concerts ("Not interested")

    @Test("An empty dismissed set is behavior-neutral")
    func emptyDismissedIsNeutral() {
        // The default: passing no dismissed ids matches the pre-dismiss shelf.
        let loved = Concert.stub(id: 1, headliningArtistId: 41)
        let baseline = ForYouShelf.recommendations(concerts: [loved], likedArtists: [stereolab])
        let withEmpty = ForYouShelf.recommendations(
            concerts: [loved], likedArtists: [stereolab], dismissedConcertIDs: [])
        #expect(withEmpty.map(\.concert.id) == baseline.map(\.concert.id))
    }

    @Test("A dismissed loved concert is filtered out of the shelf")
    func dismissedLovedFiltered() {
        let loved = Concert.stub(id: 1, headliningArtistId: 41)
        let shelf = ForYouShelf.recommendations(
            concerts: [loved], likedArtists: [stereolab], dismissedConcertIDs: [1])
        #expect(shelf.isEmpty)
    }

    @Test("A dismissed station concert is filtered out of the shelf")
    func dismissedStationFiltered() {
        let station = Concert.stub(id: 3, headliningArtistId: 700, stationRecommended: true)
        let shelf = ForYouShelf.recommendations(
            concerts: [station], likedArtists: [], stationCap: 5, dismissedConcertIDs: [3])
        #expect(shelf.isEmpty)
    }

    @Test("Dismissing one concert leaves the others on the shelf")
    func dismissedIsSurgical() {
        // Two loved concerts; dismissing only the first keeps the second.
        let a = Concert.stub(id: 60, startsOn: day(0), headliningArtistId: 41)
        let b = Concert.stub(id: 61, startsOn: day(1), headliningArtistId: 88)
        let shelf = ForYouShelf.recommendations(
            concerts: [a, b], likedArtists: [stereolab, catPower], dismissedConcertIDs: [60])
        #expect(shelf.map(\.concert.id) == [61])
        #expect(shelf[0].tier == .loved)
    }

    @Test("A dismissed id absent from the window is a no-op")
    func dismissedUnknownIDNoOp() {
        let loved = Concert.stub(id: 1, headliningArtistId: 41)
        let shelf = ForYouShelf.recommendations(
            concerts: [loved], likedArtists: [stereolab], dismissedConcertIDs: [999])
        #expect(shelf.map(\.concert.id) == [1])
    }
}
