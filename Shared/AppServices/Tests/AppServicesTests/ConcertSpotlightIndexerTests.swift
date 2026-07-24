//
//  ConcertSpotlightIndexerTests.swift
//  AppServices
//
//  Verifies `CoreSpotlightConcertIndexer`'s F3 additions: `indexName` aliases
//  `ConcertSpotlightIndex.name` (WXYCIntents) rather than a redeclared
//  literal, its `ConcertReindexer` conformance forwards to `indexConcerts(_:)`,
//  and `reindexDonations(for:)` — the pure mapping `donate(_:)` builds its
//  batch from — assigns `ConcertSpotlightDonationService.defaultPriority`
//  (no liked-artist/station-cap context exists on a Spotlight-triggered
//  reindex) and a freshly computed `endOfShowDay` expiration per concert,
//  dropping a concert whose id can't bridge to `ConcertID`.
//
//  `reindexDonations(for:)` is tested directly (a pure function) rather than
//  only through `donate(_:)`, mirroring `SpotlightIndexerTests`'s own
//  boundary: `CoreSpotlightConcertIndexer.donate(_:)`/`indexConcerts(_:)`
//  talk to a real `CSSearchableIndex`, so `donate(_:)` itself is only
//  exercised with an empty batch here (proving the early-return, not an XPC
//  round-trip).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)
import Concerts
import ConcertsTesting
import Foundation
import Testing
import WXYCIntents
@testable import AppServices

@Suite("CoreSpotlightConcertIndexer (F3 ConcertReindexer)")
struct ConcertSpotlightIndexerTests {
    @Test("indexName aliases the WXYCIntents-owned constant")
    func indexNameAliasesSharedConstant() {
        #expect(CoreSpotlightConcertIndexer.indexName == ConcertSpotlightIndex.name)
    }

    @Test("donate(_:) forwards to indexConcerts for an empty batch without throwing")
    func donateEmptyBatchDoesNotThrow() async throws {
        // CoreSpotlightConcertIndexer talks to the real CSSearchableIndex, so
        // this only proves the call doesn't throw for an empty batch —
        // indexConcerts already early-returns on empty input, avoiding an
        // XPC round-trip in a unit test. The donation-building logic is
        // covered below via reindexDonations(for:) directly, and the reindex
        // handlers' own spy-based tests in WXYCIntentsTests.
        let indexer = CoreSpotlightConcertIndexer(indexName: "wxyc.concerts.tests.\(UUID().uuidString)")

        try await indexer.donate([])
    }

    @Test("reindexDonations assigns defaultPriority and a fresh endOfShowDay expiration")
    func reindexDonationsAssignsPriorityAndExpiry() throws {
        let concert = Concert.stub(id: 1, startsOn: Concert.defaultStartsOn)

        let donations = CoreSpotlightConcertIndexer.reindexDonations(for: [concert])

        let donation = try #require(donations.first)
        #expect(donation.priority == ConcertSpotlightDonationService.defaultPriority)
        #expect(donation.expirationDate == ConcertSpotlightDonationService.endOfShowDay(concert.startsOn))
        let expectedID = try #require(ConcertID(concertID: 1))
        #expect(donation.entity.id == expectedID)
    }

    @Test("reindexDonations assigns each concert its own expiration")
    func reindexDonationsPerConcertExpiry() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let laterDay = try #require(utc.date(byAdding: .day, value: 10, to: Concert.defaultStartsOn))

        let earlyShow = Concert.stub(id: 1, startsOn: Concert.defaultStartsOn)
        let laterShow = Concert.stub(id: 2, startsOn: laterDay)

        let donations = CoreSpotlightConcertIndexer.reindexDonations(for: [earlyShow, laterShow])

        let byID = Dictionary(uniqueKeysWithValues: donations.map { ($0.entity.id, $0.expirationDate) })
        let earlyID = try #require(ConcertID(concertID: 1))
        let laterID = try #require(ConcertID(concertID: 2))
        let earlyExpiration = try #require(byID[earlyID])
        let laterExpiration = try #require(byID[laterID])
        #expect(earlyExpiration < laterExpiration)
    }

    @Test("reindexDonations drops a concert whose id can't bridge to ConcertID")
    func reindexDonationsDropsUnbridgeableID() {
        let unbridgeable = Concert.stub(id: -1)
        let bridgeable = Concert.stub(id: 1)

        let donations = CoreSpotlightConcertIndexer.reindexDonations(for: [unbridgeable, bridgeable])

        #expect(donations.map(\.entity.headlinerName) == [bridgeable.headlineName])
    }
}
#endif
