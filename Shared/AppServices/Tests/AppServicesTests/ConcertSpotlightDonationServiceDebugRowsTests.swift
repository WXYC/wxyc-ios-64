//
//  ConcertSpotlightDonationServiceDebugRowsTests.swift
//  AppServices
//
//  Verifies the OT-Q2 (#632) DEBUG-only dump `ConcertSpotlightDonationService
//  .debugRows(window:likedArtists:stationCap:dismissedConcertIDs:)` — the
//  read-only derivation the `#if DEBUG` Concert Spotlight inspector
//  (`Shared/DebugPanel`) renders. Deliberately does NOT re-litigate OT-F2's
//  own reconcile/expiry/priority unit coverage (`ConcertSpotlightDonation
//  ServiceTests`, #621) — these tests only cover the new dump derivation:
//  the persisted-donated-id/window intersection, that it never touches the
//  indexer, and that it surfaces the same id/title/priority/expirationDate
//  `reconcile` itself would have donated.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG && !os(watchOS) && !os(tvOS)
import Caching
import Concerts
import ConcertsTesting
import Core
import Foundation
import Testing
import WXYCIntents
@testable import AppServices

@Suite("ConcertSpotlightDonationService.debugRows")
struct ConcertSpotlightDonationServiceDebugRowsTests {

    @Test("debugRows is empty when nothing has ever been reconciled")
    func emptyBeforeAnyReconcile() async {
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: MockConcertSpotlightIndexer())

        let rows = await service.debugRows(window: [Concert.stub(id: 1)])

        #expect(rows.isEmpty)
    }

    @Test("debugRows returns only concerts that are both in window and persisted as donated")
    func intersectsWindowWithPersistedDonatedIDs() async throws {
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: MockConcertSpotlightIndexer())

        let staying = Concert.stub(id: 1, headliningArtistRaw: "Jessica Pratt")
        let departed = Concert.stub(id: 2, headliningArtistRaw: "Chuquimamani-Condori")
        await service.reconcile(window: [staying, departed])
        await service.reconcile(window: [staying]) // `departed` evicted — dropped out of the window.

        // Stale window (as if the caller still had `departed` in a cached
        // page) must NOT resurrect it in the dump — the persisted donated-id
        // set is the source of truth for "currently live", not the window.
        let rows = await service.debugRows(window: [staying, departed])

        #expect(rows.map(\.id) == [1])
        let row = try #require(rows.first)
        #expect(row.title == "Jessica Pratt")
    }

    @Test("debugRows reports the priority reconcile actually donated at")
    func reportsDonatedPriority() async throws {
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: MockConcertSpotlightIndexer())

        let lovedConcert = Concert.stub(id: 1, headliningArtistId: 501)
        let stationConcert = Concert.stub(id: 2, headliningArtistId: 502, stationRecommendedRank: 1)
        let restConcert = Concert.stub(id: 3, headliningArtistId: 503)
        let window = [lovedConcert, stationConcert, restConcert]
        let likedArtists = [LikedArtist(id: 501, name: "Jessica Pratt")]

        await service.reconcile(window: window, likedArtists: likedArtists, stationCap: 5)
        let rows = await service.debugRows(window: window, likedArtists: likedArtists, stationCap: 5)

        let priorityByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.priority) })
        #expect(priorityByID[1] == ConcertSpotlightDonationService.lovedPriority)
        #expect(priorityByID[2] == ConcertSpotlightDonationService.stationRecommendedPriority)
        #expect(priorityByID[3] == ConcertSpotlightDonationService.defaultPriority)
    }

    @Test("debugRows reports the same expirationDate reconcile donated")
    func reportsDonatedExpirationDate() async throws {
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: MockConcertSpotlightIndexer())

        let concert = Concert.stub(id: 1, startsOn: Concert.defaultStartsOn)
        await service.reconcile(window: [concert])

        // Literal, not `TimeZone.wxycStation`: this asserts that `debugRows`
        // reports the same expiry `reconcile` donated, and the production side
        // derives that from the constant — sharing it would make the assertion
        // hold for any value of the constant.
        let eastern = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let expected = try #require(calendar.dateInterval(of: .day, for: Concert.defaultStartsOn)?.end)

        let rows = await service.debugRows(window: [concert])
        let row = try #require(rows.first)
        #expect(row.expirationDate == expected)
    }

    @Test("debugRows never touches the indexer — read-only")
    func neverCallsTheIndexer() async {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        let concert = Concert.stub(id: 1)
        await service.reconcile(window: [concert])
        let callsAfterReconcile = await indexer.indexCalls.count

        _ = await service.debugRows(window: [concert])
        _ = await service.debugRows(window: [])
        _ = await service.debugRows(window: [Concert.stub(id: 2)])

        #expect(await indexer.indexCalls.count == callsAfterReconcile)
        #expect(await indexer.deleteCalls.isEmpty)
    }

    @Test("debugRows sorts by soonest expirationDate first")
    func sortsBySoonestExpirationFirst() async throws {
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: MockConcertSpotlightIndexer())

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let laterDay = try #require(utc.date(byAdding: .day, value: 10, to: Concert.defaultStartsOn))

        let soon = Concert.stub(id: 1, startsOn: Concert.defaultStartsOn)
        let later = Concert.stub(id: 2, startsOn: laterDay)
        await service.reconcile(window: [later, soon])

        let rows = await service.debugRows(window: [later, soon])

        #expect(rows.map(\.id) == [1, 2])
    }
}
#endif
