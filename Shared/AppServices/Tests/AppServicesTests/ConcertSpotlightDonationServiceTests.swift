//
//  ConcertSpotlightDonationServiceTests.swift
//  AppServices
//
//  Verifies the OT-F2 reconcile + expiry pipeline: a concert newly present in
//  the fetched window is donated with an `expirationDate` pinned to the end
//  of its show day in the station zone and a priority derived from
//  `ForYouShelf`'s loved/stationRecommended/rest tiers; a concert that drops
//  out of the window (a cancellation before its date) is evicted via
//  `deleteConcerts(withIdentifiers:)`; and re-running reconcile against an
//  unchanged window donates and evicts nothing (the dedup that makes this a
//  reconcile, not a watermark).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)
import Caching
import Concerts
import ConcertsTesting
import Foundation
import Testing
import WXYCIntents
@testable import AppServices

@Suite("ConcertSpotlightDonationService")
struct ConcertSpotlightDonationServiceTests {

    // MARK: - Expiry

    @Test("reconcile sets expirationDate to the end of the show's calendar day, station zone")
    func expirationDateIsEndOfShowDayStationZone() async throws {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        // `Concert.defaultStartsOn` is 2026-08-01, station (US Eastern) zone.
        let concert = Concert.stub(id: 1, startsOn: Concert.defaultStartsOn)
        await service.reconcile(window: [concert])

        let donation = try #require(await indexer.indexCalls.first?.donations.first)

        // Built independently of the service's own station-zone constants so
        // the assertion can't pass by construction.
        let eastern = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let expected = try #require(calendar.dateInterval(of: .day, for: Concert.defaultStartsOn)?.end)

        #expect(donation.expirationDate == expected)
    }

    @Test("reconcile assigns each concert its own expirationDate")
    func expirationDateIsPerConcert() async throws {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        let earlyShow = Concert.stub(id: 1, startsOn: Concert.stubInstant(hour: 0))

        // A fixed, device-timezone-independent calendar just to derive "ten
        // days later" — the assertion only cares about relative ordering.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let laterDay = try #require(utc.date(byAdding: .day, value: 10, to: Concert.defaultStartsOn))
        let laterShow = Concert.stub(id: 2, startsOn: laterDay)

        await service.reconcile(window: [earlyShow, laterShow])

        let donations = try #require(await indexer.indexCalls.first?.donations)
        let byID = Dictionary(uniqueKeysWithValues: donations.map { ($0.entity.id, $0.expirationDate) })

        let earlyID = try #require(ConcertID(concertID: 1))
        let laterID = try #require(ConcertID(concertID: 2))
        let earlyExpiration = try #require(byID[earlyID])
        let laterExpiration = try #require(byID[laterID])
        #expect(earlyExpiration < laterExpiration)
    }

    // MARK: - Eviction (cancellation before the show's date)

    @Test("reconcile evicts a concert that dropped out of the window")
    func evictsDepartedConcert() async throws {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        let staying = Concert.stub(id: 1)
        let cancelled = Concert.stub(id: 2)

        await service.reconcile(window: [staying, cancelled])
        await service.reconcile(window: [staying]) // `cancelled` dropped out — e.g. cancelled before its date.

        let deleteCalls = await indexer.deleteCalls
        #expect(deleteCalls.count == 1)
        let expectedIdentifier = try #require(ConcertID(concertID: 2)?.entityIdentifierString)
        #expect(deleteCalls.first?.identifiers == [expectedIdentifier])
    }

    @Test("reconcile does not evict a concert that stays in the window")
    func doesNotEvictConcertStillPresent() async throws {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        let concert = Concert.stub(id: 1)
        await service.reconcile(window: [concert])
        await service.reconcile(window: [concert])

        #expect(await indexer.deleteCalls.isEmpty)
    }

    @Test("reconcile does not drop a departed id from the persisted set when eviction fails")
    func failedEvictionRetainsPersistedID() async throws {
        let defaults = InMemoryDefaults()
        let workingIndexer = MockConcertSpotlightIndexer()
        let firstService = ConcertSpotlightDonationService(storage: defaults, indexer: workingIndexer)

        let staying = Concert.stub(id: 1)
        let cancelled = Concert.stub(id: 2)
        await firstService.reconcile(window: [staying, cancelled])

        // A second instance backed by the same storage, but whose indexer
        // fails eviction — the persisted set must retain `cancelled`'s id so
        // a later reconcile retries the delete instead of silently giving up.
        let failingIndexer = MockConcertSpotlightIndexer(shouldThrow: true)
        let secondService = ConcertSpotlightDonationService(storage: defaults, indexer: failingIndexer)
        await secondService.reconcile(window: [staying])

        #expect(await failingIndexer.deleteCalls.count == 1)

        // Retry with a working indexer: `cancelled` must still be treated as
        // persisted (not silently forgotten), so this reconcile retries the
        // delete rather than staying silent.
        let retryIndexer = MockConcertSpotlightIndexer()
        let retryService = ConcertSpotlightDonationService(storage: defaults, indexer: retryIndexer)
        await retryService.reconcile(window: [staying])

        #expect(await retryIndexer.deleteCalls.count == 1)
        let expectedIdentifier = try #require(ConcertID(concertID: 2)?.entityIdentifierString)
        #expect(await retryIndexer.deleteCalls.first?.identifiers == [expectedIdentifier])
    }

    // MARK: - Dedup (reconcile, not watermark)

    @Test("reconcile re-run against an unchanged window donates and evicts nothing")
    func unchangedWindowIsANoOp() async {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        let window = [Concert.stub(id: 1), Concert.stub(id: 2)]
        await service.reconcile(window: window)
        await service.reconcile(window: window)
        await service.reconcile(window: window)

        // Exactly one donation call total (from the first reconcile); the two
        // re-runs against the identical window add nothing.
        #expect(await indexer.indexCalls.count == 1)
        #expect(await indexer.deleteCalls.isEmpty)
    }

    @Test("reconcile donates only the newly-present concert when the window grows")
    func growingWindowDonatesOnlyTheNewConcert() async throws {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        await service.reconcile(window: [Concert.stub(id: 1)])
        await service.reconcile(window: [Concert.stub(id: 1), Concert.stub(id: 2)])

        #expect(await indexer.indexCalls.count == 2)
        let secondCallIDs = try #require(await indexer.indexCalls.last?.donations.map(\.entity.id))
        let expectedID = try #require(ConcertID(concertID: 2))
        #expect(secondCallIDs == [expectedID])
    }

    @Test("reconcile treats a re-appearing concert (evicted, then back in the window) as new")
    func reappearingConcertIsDonatedAgain() async throws {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        let concert = Concert.stub(id: 1)
        await service.reconcile(window: [concert]) // donated
        await service.reconcile(window: [])         // evicted
        await service.reconcile(window: [concert])  // e.g. a rescheduled show back in the window

        #expect(await indexer.indexCalls.count == 2)
        #expect(await indexer.deleteCalls.count == 1)
    }

    @Test("reconcile does not add a failed donation batch to the persisted set")
    func failedDonationDoesNotAdvancePersistedState() async {
        let defaults = InMemoryDefaults()
        let failingIndexer = MockConcertSpotlightIndexer(shouldThrow: true)
        let firstService = ConcertSpotlightDonationService(storage: defaults, indexer: failingIndexer)

        let concert = Concert.stub(id: 1)
        await firstService.reconcile(window: [concert])
        #expect(await failingIndexer.indexCalls.count == 1)

        // A retry with a working indexer must still treat the concert as new
        // (not already persisted), so the failed attempt above didn't
        // silently strand it as "donated" when it never actually indexed.
        let retryIndexer = MockConcertSpotlightIndexer()
        let retryService = ConcertSpotlightDonationService(storage: defaults, indexer: retryIndexer)
        await retryService.reconcile(window: [concert])

        #expect(await retryIndexer.indexCalls.count == 1)
    }

    @Test("reconcile is a no-op on an empty window with nothing previously donated")
    func emptyWindowNoPriorStateIsANoOp() async {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        await service.reconcile(window: [])

        #expect(await indexer.indexCalls.isEmpty)
        #expect(await indexer.deleteCalls.isEmpty)
    }

    // MARK: - Priority mapping (ForYouShelf tiers)

    @Test("reconcile maps ForYouShelf tiers to priority: loved > stationRecommended > rest")
    func priorityMapsToForYouShelfTiers() async throws {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        let lovedConcert = Concert.stub(id: 1, headliningArtistId: 501)
        let stationConcert = Concert.stub(id: 2, headliningArtistId: 502, stationRecommendedRank: 1)
        let restConcert = Concert.stub(id: 3, headliningArtistId: 503)

        await service.reconcile(
            window: [lovedConcert, stationConcert, restConcert],
            likedArtists: [LikedArtist(id: 501, name: "Jessica Pratt")],
            stationCap: 5
        )

        let donations = try #require(await indexer.indexCalls.first?.donations)
        let priorityByID = Dictionary(uniqueKeysWithValues: donations.map { ($0.entity.id, $0.priority) })

        let lovedID = try #require(ConcertID(concertID: 1))
        let stationID = try #require(ConcertID(concertID: 2))
        let restID = try #require(ConcertID(concertID: 3))
        #expect(priorityByID[lovedID] == ConcertSpotlightDonationService.lovedPriority)
        #expect(priorityByID[stationID] == ConcertSpotlightDonationService.stationRecommendedPriority)
        #expect(priorityByID[restID] == ConcertSpotlightDonationService.defaultPriority)

        // Ordering matches the design doc's tiering: loved outranks station,
        // station outranks the rest.
        #expect(ConcertSpotlightDonationService.lovedPriority > ConcertSpotlightDonationService.stationRecommendedPriority)
        #expect(ConcertSpotlightDonationService.stationRecommendedPriority > ConcertSpotlightDonationService.defaultPriority)
    }

    @Test("reconcile falls back to default priority when likedArtists and stationCap are omitted")
    func defaultsToRestTierWithNoPersonalizationInputs() async throws {
        let indexer = MockConcertSpotlightIndexer()
        let service = ConcertSpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        // Would qualify for loved/station if likes/cap were supplied, but
        // neither is — the omitted-parameter defaults must not silently rank
        // this concert above the rest tier.
        let concert = Concert.stub(id: 1, headliningArtistId: 501, stationRecommendedRank: 1)
        await service.reconcile(window: [concert])

        let donation = try #require(await indexer.indexCalls.first?.donations.first)
        #expect(donation.priority == ConcertSpotlightDonationService.defaultPriority)
    }
}

// MARK: - Test double

/// Records `indexConcerts`/`deleteConcerts` calls for assertions and
/// optionally throws to simulate a Spotlight-index failure.
actor MockConcertSpotlightIndexer: ConcertSpotlightIndexer {
    struct IndexCall: Sendable {
        let donations: [ConcertDonation]
    }
    struct DeleteCall: Sendable {
        let identifiers: [String]
    }

    private(set) var indexCalls: [IndexCall] = []
    private(set) var deleteCalls: [DeleteCall] = []
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func indexConcerts(_ donations: [ConcertDonation]) async throws {
        indexCalls.append(IndexCall(donations: donations))
        if shouldThrow {
            throw NSError(domain: "MockConcertSpotlightIndexer", code: 1)
        }
    }

    func deleteConcerts(withIdentifiers identifiers: [String]) async throws {
        deleteCalls.append(DeleteCall(identifiers: identifiers))
        if shouldThrow {
            throw NSError(domain: "MockConcertSpotlightIndexer", code: 1)
        }
    }
}
#endif
