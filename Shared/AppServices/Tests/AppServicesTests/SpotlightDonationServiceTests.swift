//
//  SpotlightDonationServiceTests.swift
//  AppServices
//
//  Verifies the F2 donation pipeline: the current playcut is indexed at
//  elevated priority on every tick; recent playcuts are batch-indexed
//  filtered by the persisted watermark; the watermark only advances after
//  a successful `indexAppEntities` return; and batches cap at 50 rows so
//  the background refresh budget can't be blown by a large playlist.
//
//  Created by Jake Bromberg on 07/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS)
import Caching
import Foundation
import Playlist
import PlaylistTesting
import Testing
import WXYCIntents
@testable import AppServices

@Suite("SpotlightDonationService")
struct SpotlightDonationServiceTests {

    // MARK: - Current playcut donation

    @Test("donateCurrentPlaycut indexes the entity at elevated priority")
    func donatesCurrentAtElevatedPriority() async {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        await service.donateCurrentPlaycut(.stub(id: 42, chronOrderID: 100))

        let calls = await indexer.calls
        #expect(calls.count == 1)
        #expect(calls.first?.entityIDs == [PlaycutID(42)])
        #expect(calls.first?.priority == SpotlightDonationService.currentPlaycutPriority)
    }

    @Test("donateCurrentPlaycut leaves the batch watermark alone")
    func currentPlaycutDoesNotTouchWatermark() async {
        // Regression: an earlier design advanced the watermark from the
        // per-tick path, which caused the first foreground tick after a
        // cold install to jump the waterline past the entire initial
        // 50-row window before the batch path could see it. The per-tick
        // path must be upsert-only.
        let defaults = InMemoryDefaults()
        let service = SpotlightDonationService(storage: defaults, indexer: MockSpotlightIndexer())

        await service.donateCurrentPlaycut(.stub(id: 1, chronOrderID: 999))

        #expect(defaults.string(forKey: SpotlightDonationService.watermarkKey) == nil)
    }

    @Test("donateCurrentPlaycut still upserts when the playcut is older than the watermark")
    func currentPlaycutRunsBelowWatermark() async {
        let defaults = InMemoryDefaults()
        defaults.set("2000", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        await service.donateCurrentPlaycut(.stub(id: 1, chronOrderID: 500))

        // Per-tick priority surfacing is independent of the batch waterline,
        // so an older playcut (e.g. a re-emit of the same playlist tick, or a
        // future "play this archived playcut" interaction) still gets indexed.
        #expect(await indexer.calls.count == 1)
        #expect(defaults.string(forKey: SpotlightDonationService.watermarkKey) == "2000")
    }

    // MARK: - Recent playcut batch

    @Test("donateRecentPlaycuts skips playcuts already at or below the watermark")
    func recentBatchSkipsStale() async throws {
        let defaults = InMemoryDefaults()
        defaults.set("50", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        await service.donateRecentPlaycuts([
            .stub(id: 1, chronOrderID: 40),
            .stub(id: 2, chronOrderID: 50),
            .stub(id: 3, chronOrderID: 60),
            .stub(id: 4, chronOrderID: 70),
        ])

        let call = try #require(await indexer.calls.first)
        #expect(call.entityIDs == [PlaycutID(3), PlaycutID(4)])
    }

    @Test("donateRecentPlaycuts caps batch size at 50")
    func recentBatchCapsAt50() async throws {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        let playcuts = (1...80).map { i in
            Playcut.stub(id: UInt64(i), chronOrderID: UInt64(i))
        }

        await service.donateRecentPlaycuts(playcuts)

        let call = try #require(await indexer.calls.first)
        #expect(call.entityIDs.count == SpotlightDonationService.batchLimit)
    }

    @Test("donateRecentPlaycuts sends the oldest 50 unseen playcuts first so the tail catches up")
    func recentBatchPrefersOldestUnseen() async throws {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        // 80 new playcuts. The first batch should be chronOrderIDs 1...50 so the
        // watermark advances to 50 and the next tick can pick up 51...80.
        let playcuts = (1...80).map { i in
            Playcut.stub(id: UInt64(i), chronOrderID: UInt64(i))
        }

        await service.donateRecentPlaycuts(playcuts)

        let call = try #require(await indexer.calls.first)
        #expect(call.entityIDs.first == PlaycutID(1))
        #expect(call.entityIDs.last == PlaycutID(50))
    }

    @Test("donateRecentPlaycuts uses batch priority, not elevated")
    func recentBatchUsesBatchPriority() async throws {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        await service.donateRecentPlaycuts([.stub(id: 1, chronOrderID: 10)])

        let call = try #require(await indexer.calls.first)
        #expect(call.priority == SpotlightDonationService.batchPriority)
        #expect(call.priority < SpotlightDonationService.currentPlaycutPriority)
    }

    @Test("donateRecentPlaycuts advances the watermark to the highest indexed chronOrderID")
    func recentBatchAdvancesWatermark() async {
        let defaults = InMemoryDefaults()
        let service = SpotlightDonationService(storage: defaults, indexer: MockSpotlightIndexer())

        await service.donateRecentPlaycuts([
            .stub(id: 1, chronOrderID: 10),
            .stub(id: 2, chronOrderID: 30),
            .stub(id: 3, chronOrderID: 20),
        ])

        #expect(defaults.string(forKey: SpotlightDonationService.watermarkKey) == "30")
    }

    @Test("donateRecentPlaycuts does not advance the watermark when indexing fails")
    func recentBatchDoesNotAdvanceOnFailure() async {
        let defaults = InMemoryDefaults()
        defaults.set("5", forKey: SpotlightDonationService.watermarkKey)
        let service = SpotlightDonationService(
            storage: defaults,
            indexer: MockSpotlightIndexer(shouldThrow: true)
        )

        await service.donateRecentPlaycuts([.stub(id: 1, chronOrderID: 100)])

        #expect(defaults.string(forKey: SpotlightDonationService.watermarkKey) == "5")
    }

    @Test("donateRecentPlaycuts does not call the indexer when every playcut is stale")
    func recentBatchSkipsWhenAllStale() async {
        let defaults = InMemoryDefaults()
        defaults.set("100", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        await service.donateRecentPlaycuts([
            .stub(id: 1, chronOrderID: 10),
            .stub(id: 2, chronOrderID: 100),
        ])

        #expect(await indexer.calls.isEmpty)
        #expect(defaults.string(forKey: SpotlightDonationService.watermarkKey) == "100")
    }

    @Test("donateRecentPlaycuts is a no-op on an empty playlist")
    func recentBatchSkipsWhenEmpty() async {
        let defaults = InMemoryDefaults()
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        await service.donateRecentPlaycuts([])

        #expect(await indexer.calls.isEmpty)
        #expect(defaults.string(forKey: SpotlightDonationService.watermarkKey) == nil)
    }

    // MARK: - Watermark persistence

    @Test("Watermark persists across service instances backed by the same storage")
    func watermarkPersistsAcrossInstances() async {
        let defaults = InMemoryDefaults()
        let first = SpotlightDonationService(storage: defaults, indexer: MockSpotlightIndexer())

        // Only the batch path advances the watermark; a cross-instance test
        // has to drive it there so the second instance sees the persisted
        // state.
        await first.donateRecentPlaycuts([.stub(id: 1, chronOrderID: 777)])

        let secondIndexer = MockSpotlightIndexer()
        let second = SpotlightDonationService(storage: defaults, indexer: secondIndexer)

        // Playcut 500 is stale relative to the persisted 777.
        await second.donateRecentPlaycuts([.stub(id: 2, chronOrderID: 500)])

        #expect(await secondIndexer.calls.isEmpty)
        #expect(defaults.string(forKey: SpotlightDonationService.watermarkKey) == "777")
    }
}

// MARK: - Test double

/// Records `indexAppEntities` calls for assertions and optionally throws to
/// simulate a Spotlight-index failure.
actor MockSpotlightIndexer: SpotlightIndexer {
    struct Call: Sendable {
        let entityIDs: [PlaycutID]
        let priority: Int
    }

    private(set) var calls: [Call] = []
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func indexPlaycuts(_ entities: [PlaycutEntity], priority: Int) async throws {
        calls.append(Call(entityIDs: entities.map(\.id), priority: priority))
        if shouldThrow {
            throw NSError(domain: "MockSpotlightIndexer", code: 1)
        }
    }
}
#endif
