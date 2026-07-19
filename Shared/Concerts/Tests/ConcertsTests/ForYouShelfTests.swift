//
//  ForYouShelfTests.swift
//  Concerts
//
//  Coverage for the on-device For You recommendation engine (WXYC/wxyc-ios-64#493):
//  loved/similar tiering, reason-line selection, loved-then-similar ordering, and
//  the injected similar-tier count cap. The engine is pure — no likes store, no
//  flag provider, no clock — so the cap arrives as a parameter and likes arrive
//  as plain fixtures (WXYC-canonical artists).
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

    // MARK: - Cold start

    @Test("No likes yields an empty shelf (cold start)")
    func coldStart() {
        let concert = Concert.stub(id: 1, headliningArtistId: 41,
                                   similarArtists: [SimilarArtist(artistId: 88, weight: 0.9)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [], similarCap: 3)
        #expect(shelf.isEmpty)
    }

    // MARK: - Loved tier

    @Test("A liked headliner surfaces a loved card whose reason names the headliner")
    func lovedCard() {
        let concert = Concert.stub(id: 1, headliningArtistRaw: "Stereolab",
                                   headliningArtistId: 41, similarArtists: nil)
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab], similarCap: 3)
        #expect(shelf.count == 1)
        #expect(shelf[0].concert.id == 1)
        #expect(shelf[0].tier == .loved)
        #expect(shelf[0].reasonArtistName == "Stereolab")
    }

    @Test("Loved cards preserve the input window order")
    func lovedPreservesOrder() {
        let a = Concert.stub(id: 60, startsOn: day(0), headliningArtistId: 41, similarArtists: nil)
        let b = Concert.stub(id: 61, startsOn: day(1), headliningArtistId: 88, similarArtists: nil)
        let shelf = ForYouShelf.recommendations(concerts: [a, b], likedArtists: [catPower, stereolab], similarCap: 3)
        #expect(shelf.map(\.concert.id) == [60, 61])
    }

    // MARK: - Similar tier

    @Test("A liked affinity-neighbor surfaces a similar card whose reason names the liked artist")
    func similarCard() {
        // Headliner (Jessica Pratt, 512) is not liked, but Stereolab (41) is a neighbor.
        let concert = Concert.stub(id: 2, headliningArtistRaw: "Jessica Pratt", headliningArtistId: 512,
                                   similarArtists: [SimilarArtist(artistId: 41, weight: 0.8)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab], similarCap: 3)
        #expect(shelf.count == 1)
        #expect(shelf[0].tier == .similar(weight: 0.8))
        #expect(shelf[0].reasonArtistName == "Stereolab")
    }

    @Test("Equal-weight liked neighbors break the reason tie toward the smaller artist id")
    func similarReasonTieBreaksBySmallerID() {
        // Both Stereolab (41) and Cat Power (88) are liked neighbors at the same
        // weight; the smaller id (41 → Stereolab) is the deterministic reason.
        let concert = Concert.stub(id: 4, headliningArtistId: 999,
            similarArtists: [SimilarArtist(artistId: 88, weight: 0.7), SimilarArtist(artistId: 41, weight: 0.7)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab, catPower], similarCap: 3)
        #expect(shelf.count == 1)
        #expect(shelf[0].reasonArtistName == "Stereolab")
        #expect(shelf[0].tier == .similar(weight: 0.7))
    }

    @Test("An empty similar_artists array yields no similar card")
    func emptyNeighborsNoCard() {
        // Present-but-empty behaves exactly like nil: nothing to intersect.
        let concert = Concert.stub(id: 6, headliningArtistId: 999, similarArtists: [])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab], similarCap: 3)
        #expect(shelf.isEmpty)
    }

    @Test("The similar reason names the highest-weight intersecting liked artist")
    func similarReasonPicksHighestWeight() {
        // Both Cat Power (88, w=0.4) and Stereolab (41, w=0.9) are liked neighbors;
        // Stereolab has the higher weight, so it names the reason.
        let concert = Concert.stub(id: 3, headliningArtistId: 999,
            similarArtists: [SimilarArtist(artistId: 88, weight: 0.4), SimilarArtist(artistId: 41, weight: 0.9)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab, catPower], similarCap: 3)
        #expect(shelf.count == 1)
        #expect(shelf[0].reasonArtistName == "Stereolab")
        #expect(shelf[0].tier == .similar(weight: 0.9))
    }

    @Test("A concert whose neighbors are all unliked yields no card")
    func noMatchNoCard() {
        let concert = Concert.stub(id: 50, headliningArtistId: 999,
                                   similarArtists: [SimilarArtist(artistId: 777, weight: 0.9)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab], similarCap: 3)
        #expect(shelf.isEmpty)
    }

    @Test("Similar cards rank by weight, descending")
    func similarRankedByWeight() {
        let low = Concert.stub(id: 20, headliningArtistId: 901, similarArtists: [SimilarArtist(artistId: 41, weight: 0.3)])
        let high = Concert.stub(id: 21, headliningArtistId: 902, similarArtists: [SimilarArtist(artistId: 41, weight: 0.9)])
        let mid = Concert.stub(id: 22, headliningArtistId: 903, similarArtists: [SimilarArtist(artistId: 41, weight: 0.6)])
        let shelf = ForYouShelf.recommendations(concerts: [low, high, mid], likedArtists: [stereolab], similarCap: 5)
        #expect(shelf.map(\.concert.id) == [21, 22, 20])
    }

    @Test("Equal-weight similar cards tie-break by soonest date then id")
    func similarTieBreak() {
        let later = Concert.stub(id: 70, startsOn: day(2), headliningArtistId: 901,
                                 similarArtists: [SimilarArtist(artistId: 41, weight: 0.5)])
        let sooner = Concert.stub(id: 71, startsOn: day(1), headliningArtistId: 902,
                                  similarArtists: [SimilarArtist(artistId: 41, weight: 0.5)])
        let shelf = ForYouShelf.recommendations(concerts: [later, sooner], likedArtists: [stereolab], similarCap: 3)
        #expect(shelf.map(\.concert.id) == [71, 70])
    }

    // MARK: - Tier precedence & de-duplication

    @Test("Loved cards sort before similar cards, regardless of similar weight")
    func lovedBeforeSimilar() {
        let similar = Concert.stub(id: 10, headliningArtistId: 999,
                                   similarArtists: [SimilarArtist(artistId: 41, weight: 0.95)])
        let loved = Concert.stub(id: 11, headliningArtistId: 88, similarArtists: nil)
        let shelf = ForYouShelf.recommendations(concerts: [similar, loved],
                                                likedArtists: [stereolab, catPower], similarCap: 3)
        #expect(shelf.map(\.concert.id) == [11, 10])
        #expect(shelf[0].tier == .loved)
        #expect(shelf[1].tier == .similar(weight: 0.95))
    }

    @Test("A concert that is both loved and a similar match appears once, as loved")
    func lovedTakesPrecedenceOverSimilar() {
        // Headliner Stereolab (41, liked) AND Cat Power (88, liked) is a neighbor.
        let concert = Concert.stub(id: 5, headliningArtistId: 41,
                                   similarArtists: [SimilarArtist(artistId: 88, weight: 0.9)])
        let shelf = ForYouShelf.recommendations(concerts: [concert],
                                                likedArtists: [stereolab, catPower], similarCap: 3)
        #expect(shelf.count == 1)
        #expect(shelf[0].tier == .loved)
        #expect(shelf[0].reasonArtistName == "Stereolab")
    }

    // MARK: - Noise cap

    @Test("The similar tier is capped to `similarCap` by weight; loved is uncapped")
    func similarCapEnforced() {
        let loved1 = Concert.stub(id: 30, headliningArtistId: 41, similarArtists: nil)
        let loved2 = Concert.stub(id: 31, headliningArtistId: 88, similarArtists: nil)
        let s1 = Concert.stub(id: 32, headliningArtistId: 901, similarArtists: [SimilarArtist(artistId: 41, weight: 0.9)])
        let s2 = Concert.stub(id: 33, headliningArtistId: 902, similarArtists: [SimilarArtist(artistId: 41, weight: 0.7)])
        let s3 = Concert.stub(id: 34, headliningArtistId: 903, similarArtists: [SimilarArtist(artistId: 41, weight: 0.5)])
        let shelf = ForYouShelf.recommendations(concerts: [loved1, loved2, s1, s2, s3],
                                                likedArtists: [stereolab, catPower], similarCap: 2)
        #expect(shelf.filter { $0.tier == .loved }.count == 2)
        let similarIDs = shelf.compactMap { rec -> Int? in
            if case .similar = rec.tier { return rec.concert.id } else { return nil }
        }
        #expect(similarIDs == [32, 33])
    }

    @Test("A cap of 0 drops every similar card but keeps loved cards")
    func zeroCap() {
        let loved = Concert.stub(id: 40, headliningArtistId: 41, similarArtists: nil)
        let similar = Concert.stub(id: 42, headliningArtistId: 901, similarArtists: [SimilarArtist(artistId: 41, weight: 0.9)])
        let shelf = ForYouShelf.recommendations(concerts: [loved, similar], likedArtists: [stereolab], similarCap: 0)
        #expect(shelf.map(\.concert.id) == [40])
        #expect(shelf[0].tier == .loved)
    }

    @Test("A negative cap behaves like zero: no similar cards, loved untouched")
    func negativeCap() {
        let loved = Concert.stub(id: 43, headliningArtistId: 41, similarArtists: nil)
        let similar = Concert.stub(id: 44, headliningArtistId: 901, similarArtists: [SimilarArtist(artistId: 41, weight: 0.9)])
        let shelf = ForYouShelf.recommendations(concerts: [loved, similar], likedArtists: [stereolab], similarCap: -1)
        #expect(shelf.map(\.concert.id) == [43])
        #expect(shelf[0].tier == .loved)
    }

    // MARK: - List-relative noise floor (#354 review guidance)

    @Test("A liked neighbor below the list-relative floor does not surface a card")
    func belowFloorDropped() {
        // Liked Stereolab (41) is a weak 0.3 neighbor in a list topped at 1.0;
        // 0.3 < 0.5 × 1.0, so the default floor drops it.
        let concert = Concert.stub(id: 80, headliningArtistId: 900,
            similarArtists: [SimilarArtist(artistId: 901, weight: 1.0), SimilarArtist(artistId: 41, weight: 0.3)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab], similarCap: 3)
        #expect(shelf.isEmpty)
    }

    @Test("Lowering the relative floor lets a weak-but-liked neighbor surface")
    func lowerFloorAdmits() {
        let concert = Concert.stub(id: 81, headliningArtistId: 900,
            similarArtists: [SimilarArtist(artistId: 901, weight: 1.0), SimilarArtist(artistId: 41, weight: 0.3)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab],
                                                similarCap: 3, relativeFloor: 0.2)
        #expect(shelf.count == 1)
        #expect(shelf[0].tier == .similar(weight: 0.3))
        #expect(shelf[0].reasonArtistName == "Stereolab")
    }

    @Test("The floor is list-relative: the same absolute weight surfaces in a sparse list but not a dense one")
    func floorIsListRelative() {
        // Identical liked-Stereolab weight (0.4) in both concerts:
        //  - dense list topped at 1.0 → 0.4 < 0.5 × 1.0 → dropped
        //  - sparse list topped at 0.4 → 0.4 ≥ 0.5 × 0.4 (= 0.2) → kept
        let dense = Concert.stub(id: 82, headliningArtistId: 900,
            similarArtists: [SimilarArtist(artistId: 901, weight: 1.0), SimilarArtist(artistId: 41, weight: 0.4)])
        let sparse = Concert.stub(id: 83, headliningArtistId: 902,
            similarArtists: [SimilarArtist(artistId: 41, weight: 0.4)])
        let shelf = ForYouShelf.recommendations(concerts: [dense, sparse], likedArtists: [stereolab], similarCap: 3)
        #expect(shelf.map(\.concert.id) == [83])
    }

    @Test("A relative floor of 0 admits every liked neighbor")
    func zeroFloorAdmitsAll() {
        let concert = Concert.stub(id: 84, headliningArtistId: 900,
            similarArtists: [SimilarArtist(artistId: 901, weight: 1.0), SimilarArtist(artistId: 41, weight: 0.01)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab],
                                                similarCap: 3, relativeFloor: 0)
        #expect(shelf.count == 1)
        #expect(shelf[0].tier == .similar(weight: 0.01))
    }

    @Test("A neighbor exactly at the relative floor qualifies (inclusive boundary)")
    func atFloorQualifies() {
        // 0.5 == 0.5 × 1.0 → the boundary is inclusive.
        let concert = Concert.stub(id: 85, headliningArtistId: 900,
            similarArtists: [SimilarArtist(artistId: 901, weight: 1.0), SimilarArtist(artistId: 41, weight: 0.5)])
        let shelf = ForYouShelf.recommendations(concerts: [concert], likedArtists: [stereolab], similarCap: 3)
        #expect(shelf.count == 1)
        #expect(shelf[0].tier == .similar(weight: 0.5))
    }
}
