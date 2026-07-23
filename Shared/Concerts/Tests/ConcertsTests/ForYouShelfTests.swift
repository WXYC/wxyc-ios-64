//
//  ForYouShelfTests.swift
//  Concerts
//
//  Coverage for the on-device "Heard on WXYC" recommendation engine
//  (WXYC/wxyc-ios-64#493): loved / station tiering, loved-then-station ordering,
//  the injected station-tier cap, and dismissal. The station tier's cap
//  membership is selected by the server's `stationRecommendedRank` ascending
//  (WXYC/wxyc-ios-64#594); the kept set still displays by concert date
//  ascending. The engine is pure — no likes store, no flag provider, no clock —
//  so the cap arrives as a parameter and likes arrive as plain fixtures
//  (WXYC-canonical artists).
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
        let station = Concert.stub(id: 3, headliningArtistId: 700, stationRecommendedRank: 1)
        let loved = Concert.stub(id: 11, headliningArtistId: 41)
        let shelf = ForYouShelf.recommendations(
            concerts: [station, loved], likedArtists: [stereolab], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [11, 3])
        #expect(shelf[0].tier == .loved)
        #expect(shelf[1].tier == .stationRecommended)
    }

    @Test("A concert that qualifies as both loved and station appears once, as loved")
    func stationDedupWithLoved() {
        let concert = Concert.stub(id: 6, headliningArtistId: 41, stationRecommendedRank: 1)
        let shelf = ForYouShelf.recommendations(
            concerts: [concert], likedArtists: [stereolab], stationCap: 5)
        #expect(shelf.count == 1)
        #expect(shelf[0].tier == .loved)
    }

    @Test("""
        A concert both loved and station-gated appears once, as loved, and the \
        station tier backfills from the next-lowest-rank unclaimed concert
        """)
    func stationBackfillsPastALovedClaim() {
        // The rank-1 concert is also loved, so it's claimed by the loved tier and
        // excluded from station eligibility entirely; with a cap of 2 the station
        // tier backfills from rank 2 and rank 3 — the next-lowest-rank unclaimed
        // concerts — rather than surfacing only one card.
        let claimedByLoved = Concert.stub(id: 60, headliningArtistId: 41, stationRecommendedRank: 1)
        let rank2 = Concert.stub(id: 61, startsOn: day(1), headliningArtistId: 920, stationRecommendedRank: 2)
        let rank3 = Concert.stub(id: 62, startsOn: day(0), headliningArtistId: 921, stationRecommendedRank: 3)
        let shelf = ForYouShelf.recommendations(
            concerts: [claimedByLoved, rank2, rank3], likedArtists: [stereolab], stationCap: 2)
        #expect(shelf.count == 3)
        #expect(shelf[0].concert.id == 60)
        #expect(shelf[0].tier == .loved)
        // The backfilled station pair displays by date ascending: rank3 (day 0)
        // before rank2 (day 1).
        #expect(shelf[1].concert.id == 62)
        #expect(shelf[2].concert.id == 61)
        #expect(shelf[1].tier == .stationRecommended)
        #expect(shelf[2].tier == .stationRecommended)
    }

    // MARK: - Station recommended (#577; rank-based cap selection #594)

    @Test("Cold start (zero likes) surfaces station cards, soonest first")
    func coldStartStationCards() {
        // No likes at all — the case the station tier exists to fill. Every
        // concert fits inside the cap, so all three are kept and displayed by
        // date; the ranks are deliberately out of date order to show that,
        // once selected, display is by date, not rank.
        let deerhoof = Concert.stub(id: 100, startsOn: day(2), headliningArtistRaw: "Deerhoof",
                                    headliningArtistId: 201, stationRecommendedRank: 3)
        let rem = Concert.stub(id: 101, startsOn: day(0), headliningArtistRaw: "R.E.M.",
                               headliningArtistId: 202, stationRecommendedRank: 1)
        let luna = Concert.stub(id: 102, startsOn: day(1), headliningArtistRaw: "Luna",
                                headliningArtistId: 203, stationRecommendedRank: 2)
        let shelf = ForYouShelf.recommendations(
            concerts: [deerhoof, rem, luna], likedArtists: [], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [101, 102, 100])
        #expect(shelf.allSatisfy { $0.tier == .stationRecommended })
    }

    @Test("Station cards display by concert date ascending, not by rank")
    func stationOrderedByDateAscending() {
        // `later` is the stronger rank (1) but the later date; `sooner` is the
        // weaker rank (2) but the earlier date. Both fit inside the cap, so both
        // are kept, and display order follows the date, not the rank.
        let later = Concert.stub(id: 20, startsOn: day(2), headliningArtistId: 901, stationRecommendedRank: 1)
        let sooner = Concert.stub(id: 21, startsOn: day(1), headliningArtistId: 902, stationRecommendedRank: 2)
        let shelf = ForYouShelf.recommendations(
            concerts: [later, sooner], likedArtists: [], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [21, 20])
    }

    @Test("Same-day station cards tie-break by concert id ascending")
    func stationTieBreaksByID() {
        let higherID = Concert.stub(id: 23, startsOn: day(1), headliningArtistId: 901, stationRecommendedRank: 1)
        let lowerID = Concert.stub(id: 22, startsOn: day(1), headliningArtistId: 902, stationRecommendedRank: 2)
        let shelf = ForYouShelf.recommendations(
            concerts: [higherID, lowerID], likedArtists: [], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [22, 23])
    }

    @Test("The station tier cap selects membership by rank ascending, not by date")
    func stationCapSelectsByRankAscending() {
        // rank3 is the soonest date of the three but must be excluded — cap
        // membership is decided purely by rank. The kept pair {rank1, rank2}
        // then displays by date ascending: rank2 (day 1) before rank1 (day 2).
        let rank1 = Concert.stub(id: 10, startsOn: day(2), headliningArtistId: 901, stationRecommendedRank: 1)
        let rank2 = Concert.stub(id: 11, startsOn: day(1), headliningArtistId: 902, stationRecommendedRank: 2)
        let rank3 = Concert.stub(id: 12, startsOn: day(0), headliningArtistId: 903, stationRecommendedRank: 3)
        let shelf = ForYouShelf.recommendations(
            concerts: [rank1, rank2, rank3], likedArtists: [], stationCap: 2)
        #expect(shelf.map(\.concert.id) == [11, 10])
        #expect(shelf.allSatisfy { $0.tier == .stationRecommended })
    }

    @Test("Exactly `stationCap` eligible concerts are all kept")
    func capBoundaryExactlyStationCap() {
        let a = Concert.stub(id: 50, startsOn: day(0), headliningArtistId: 910, stationRecommendedRank: 1)
        let b = Concert.stub(id: 51, startsOn: day(1), headliningArtistId: 911, stationRecommendedRank: 2)
        let shelf = ForYouShelf.recommendations(
            concerts: [a, b], likedArtists: [], stationCap: 2)
        #expect(Set(shelf.map(\.concert.id)) == [50, 51])
    }

    @Test("One more than `stationCap` eligible concerts keeps exactly the `stationCap` lowest ranks")
    func capBoundaryOneOverStationCap() {
        let a = Concert.stub(id: 52, startsOn: day(0), headliningArtistId: 912, stationRecommendedRank: 1)
        let b = Concert.stub(id: 53, startsOn: day(1), headliningArtistId: 913, stationRecommendedRank: 2)
        let c = Concert.stub(id: 54, startsOn: day(2), headliningArtistId: 914, stationRecommendedRank: 3)
        let shelf = ForYouShelf.recommendations(
            concerts: [a, b, c], likedArtists: [], stationCap: 2)
        #expect(shelf.map(\.concert.id) == [52, 53])
    }

    @Test("A concert with a null stationRecommendedRank never appears in the station tier")
    func nullRankExcludedFromStationTier() {
        let ranked = Concert.stub(id: 15, headliningArtistId: 903, stationRecommendedRank: 1)
        let unranked = Concert.stub(id: 16, headliningArtistId: 904, stationRecommendedRank: nil)
        let shelf = ForYouShelf.recommendations(
            concerts: [ranked, unranked], likedArtists: [], stationCap: 5)
        #expect(shelf.map(\.concert.id) == [15])
    }

    @Test("No station cards when no concert carries a stationRecommendedRank")
    func noStationWhenNoneRanked() {
        // Every concert has a nil rank (explicitly or by default) → an empty
        // shelf, even with the tier turned on.
        let explicitNil = Concert.stub(id: 13, headliningArtistId: 901, stationRecommendedRank: nil)
        let defaultNil = Concert.stub(id: 14, headliningArtistId: 902)
        let shelf = ForYouShelf.recommendations(
            concerts: [explicitNil, defaultNil], likedArtists: [], stationCap: 5)
        #expect(shelf.isEmpty)
    }

    @Test("The station tier is off by default (stationCap defaults to 0)")
    func stationOffByDefault() {
        // The engine default keeps the likes-only shelf: a caller must opt in with
        // a positive stationCap to turn the tier on.
        let concert = Concert.stub(id: 30, headliningArtistId: 901, stationRecommendedRank: 1)
        #expect(ForYouShelf.recommendations(concerts: [concert], likedArtists: []).isEmpty)
    }

    @Test("A non-positive stationCap yields no station cards", arguments: [0, -1, -5])
    func nonPositiveCapYieldsNoStationCards(cap: Int) {
        let concert = Concert.stub(id: 31, headliningArtistId: 930, stationRecommendedRank: 1)
        let shelf = ForYouShelf.recommendations(
            concerts: [concert], likedArtists: [], stationCap: cap)
        #expect(shelf.isEmpty)
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
        let station = Concert.stub(id: 3, headliningArtistId: 700, stationRecommendedRank: 1)
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
