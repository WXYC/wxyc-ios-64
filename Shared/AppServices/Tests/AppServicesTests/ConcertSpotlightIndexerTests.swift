//
//  ConcertSpotlightIndexerTests.swift
//  AppServices
//
//  Verifies `CoreSpotlightEntityIndexer<ConcertEntity>`'s F3 additions
//  (#758): its `ConcertSpotlightIndexer` conformance forwards to
//  `indexConcerts(_:)`, and `reindexDonations(for:)` — the pure mapping
//  `donate(_:)` builds its batch from — assigns
//  `ConcertSpotlightDonationService.defaultPriority` (no liked-artist/
//  station-cap context exists on a Spotlight-triggered reindex) and a
//  freshly computed `endOfShowDay` expiration per concert, dropping a
//  concert whose id can't bridge to `ConcertID`.
//
//  `reindexDonations(for:)` is tested directly (a pure function) rather than
//  only through `donate(_:)`, mirroring `SpotlightIndexerTests`'s own
//  boundary: `CoreSpotlightEntityIndexer<ConcertEntity>.donate(_:)`/
//  `indexConcerts(_:)` talk to a real `CSSearchableIndex`, so `donate(_:)`
//  itself is only exercised with an empty batch here (proving the
//  early-return, not an XPC round-trip).
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

@Suite("CoreSpotlightEntityIndexer<ConcertEntity> (F3 SpotlightReindexer)")
struct ConcertSpotlightIndexerTests {
    @Test("indexName echoes back the name passed at init")
    func indexNameEchoesInit() {
        let indexer = CoreSpotlightEntityIndexer<ConcertEntity>(indexName: SpotlightIndexName.concerts)
        #expect(indexer.indexName == SpotlightIndexName.concerts)
    }

    @Test("donate(_:) forwards to indexConcerts for an empty batch without throwing")
    func donateEmptyBatchDoesNotThrow() async throws {
        // CoreSpotlightEntityIndexer talks to the real CSSearchableIndex, so
        // this only proves the call doesn't throw for an empty batch —
        // indexConcerts already early-returns on empty input, avoiding an
        // XPC round-trip in a unit test. The donation-building logic is
        // covered below via reindexDonations(for:) directly, and the reindex
        // handlers' own spy-based tests in WXYCIntentsTests.
        let indexer = CoreSpotlightEntityIndexer<ConcertEntity>(indexName: "wxyc.concerts.tests.\(UUID().uuidString)")

        try await indexer.donate([])
    }

    @Test("reindexDonations assigns defaultPriority and a fresh endOfShowDay expiration")
    func reindexDonationsAssignsPriorityAndExpiry() throws {
        let concert = Concert.stub(id: 1, startsOn: Concert.defaultStartsOn)

        let donations = CoreSpotlightEntityIndexer<ConcertEntity>.reindexDonations(for: [concert])

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

        let donations = CoreSpotlightEntityIndexer<ConcertEntity>.reindexDonations(for: [earlyShow, laterShow])

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

        let donations = CoreSpotlightEntityIndexer<ConcertEntity>.reindexDonations(for: [unbridgeable, bridgeable])

        #expect(donations.map(\.entity.headlinerName) == [bridgeable.headlineName])
    }
}
#endif
