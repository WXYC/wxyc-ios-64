//
//  SpotlightDonationServiceTests.swift
//  AppServices
//
//  Verifies the F2 donation pipeline: the current playcut is indexed at
//  elevated priority on every tick; recent playcuts are batch-indexed
//  filtered by the persisted watermark; the watermark only advances after
//  a successful `indexAppEntities` return; and batches cap at 50 rows so
//  the background refresh budget can't be blown by a large playlist. C6
//  adds `donateArtists(from:)`, which mirrors the batch playcut path
//  against the separate `wxyc.artists` named index: dedup by normalized
//  artist name (mixed-case/whitespace/"feat." variants collapse to one
//  entity), cap at `batchLimit`, donate at `batchPriority`.
//
//  Created by Jake Bromberg on 07/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)
import Analytics
import AnalyticsTesting
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

    @Test("donateCurrentPlaycut dedups byte-identical consecutive calls")
    func currentPlaycutDedupsIdenticalCalls() async {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)
        let playcut = Playcut.stub(id: 1, chronOrderID: 100)

        await service.donateCurrentPlaycut(playcut)
        await service.donateCurrentPlaycut(playcut)
        await service.donateCurrentPlaycut(playcut)

        // Spotlight upserts are idempotent, but each call is an XPC round-trip
        // to `searchd` — PlaylistService re-broadcasts a downstream metadata
        // enrichment that doesn't touch playcuts.first would burn one round-trip
        // per re-broadcast without this dedup.
        #expect(await indexer.calls.count == 1)
    }

    @Test("donateCurrentPlaycut re-donates when the playcut's metadata changes")
    func currentPlaycutReindexesOnMetadataChange() async {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        // Same chronOrderID, different artwork — the enrichment path we want to
        // preserve: a metadata landing on the on-air playcut should refresh the
        // Spotlight attribute set.
        let v1 = Playcut.stub(id: 1, chronOrderID: 100, artworkURL: nil)
        let v2 = Playcut.stub(id: 1, chronOrderID: 100, artworkURL: URL(string: "https://example.com/art.jpg"))

        await service.donateCurrentPlaycut(v1)
        await service.donateCurrentPlaycut(v2)

        #expect(await indexer.calls.count == 2)
    }

    @Test("donateCurrentPlaycut dedup ignores failed calls so a retry re-attempts the same playcut")
    func currentPlaycutFailureBypassesDedup() async {
        let indexer = MockSpotlightIndexer(shouldThrow: true)
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)
        let playcut = Playcut.stub(id: 1, chronOrderID: 100)

        await service.donateCurrentPlaycut(playcut)
        await service.donateCurrentPlaycut(playcut)

        // The dedup state advances only on a successful indexer return, so a
        // transient failure doesn't strand the playcut in a "already donated"
        // state that the next tick would silently skip.
        #expect(await indexer.calls.count == 2)
    }

    @Test("donateCurrentPlaycut swallows indexer failures and leaves the watermark untouched")
    func currentPlaycutFailureIsolation() async {
        // Defends the 866d87ab regression window: the earlier design advanced
        // the watermark from the per-tick success path. This test explicitly
        // covers a throwing indexer to guarantee that a future refactor
        // reintroducing watermark writes here fails a test, and to lock in
        // the swallow-and-log contract (the actor method is `async` but not
        // throwing — the throw must not propagate to the caller).
        let defaults = InMemoryDefaults()
        defaults.set("500", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer(shouldThrow: true)
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        await service.donateCurrentPlaycut(.stub(id: 1, chronOrderID: 999))

        #expect(await indexer.calls.count == 1)
        #expect(defaults.string(forKey: SpotlightDonationService.watermarkKey) == "500")
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

    // MARK: - Artist donation (C6)

    @Test("donateArtists indexes one deduped entity per normalized artist name")
    func donateArtistsDedupsNameVariants() async throws {
        let artistIndexer = MockArtistSpotlightIndexer()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: artistIndexer
        )

        await service.donateArtists(from: [
            .stub(id: 1, artistName: "Stereolab"),
            .stub(id: 2, artistName: "Stereolab feat. Nurse With Wound"),
            .stub(id: 3, artistName: "  STEREOLAB  "),
            .stub(id: 4, artistName: "Juana Molina"),
        ])

        let calls = await artistIndexer.calls
        #expect(calls.count == 1)
        let entities = try #require(calls.first?.entities)
        #expect(entities.count == 2)
    }

    @Test("donateArtists carries the play count per artist")
    func donateArtistsCarriesPlayCount() async throws {
        let artistIndexer = MockArtistSpotlightIndexer()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: artistIndexer
        )

        await service.donateArtists(from: [
            .stub(id: 1, artistName: "Stereolab"),
            .stub(id: 2, artistName: "Stereolab feat. Nurse With Wound"),
            .stub(id: 3, artistName: "Juana Molina"),
        ])

        let calls = await artistIndexer.calls
        let entities = try #require(calls.first?.entities)
        let stereolabID = ArtistEntity(artistName: "Stereolab").id
        let stereolabEntity = try #require(entities.first { $0.id == stereolabID })
        #expect(stereolabEntity.playCount == 2)
    }

    @Test("donateArtists uses batch priority")
    func donateArtistsUsesBatchPriority() async throws {
        let artistIndexer = MockArtistSpotlightIndexer()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: artistIndexer
        )

        await service.donateArtists(from: [.stub(id: 1, artistName: "Stereolab")])

        let call = try #require(await artistIndexer.calls.first)
        #expect(call.priority == SpotlightDonationService.batchPriority)
    }

    @Test("donateArtists caps the deduped batch at batchLimit")
    func donateArtistsCapsAtBatchLimit() async throws {
        let artistIndexer = MockArtistSpotlightIndexer()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: artistIndexer
        )

        let playcuts = (1...80).map { i in
            Playcut.stub(id: UInt64(i), artistName: "Artist \(i)")
        }

        await service.donateArtists(from: playcuts)

        let call = try #require(await artistIndexer.calls.first)
        #expect(call.entities.count == SpotlightDonationService.batchLimit)
    }

    @Test("donateArtists is a no-op on an empty playlist")
    func donateArtistsSkipsWhenEmpty() async {
        let artistIndexer = MockArtistSpotlightIndexer()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: artistIndexer
        )

        await service.donateArtists(from: [])

        #expect(await artistIndexer.calls.isEmpty)
    }

    @Test("donateArtists swallows a throwing indexer without propagating or crashing")
    func donateArtistsSwallowsIndexerFailure() async {
        // The actor method is `async` but not throwing — an indexer failure
        // must be logged and swallowed (mirroring the playcut-batch path) so a
        // transient Spotlight error on one tick can't tear down the donation
        // task. Reaching the assertion below at all proves the throw did not
        // propagate.
        let artistIndexer = MockArtistSpotlightIndexer(shouldThrow: true)
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: artistIndexer
        )

        await service.donateArtists(from: [.stub(id: 1, artistName: "Stereolab")])

        #expect(await artistIndexer.calls.count == 1)
    }

    // MARK: - Batch donation tick (production entry point)

    @Test("donateBatch donates both playcuts and artists from one refresh tick")
    func donateBatchDonatesPlaycutsAndArtists() async throws {
        // Proves the single entry point both production call sites use
        // (`BackgroundRefreshController.handleRefresh` and
        // `Singletonia.startSpotlightDonation`) drives the `wxyc.artists`
        // index on the same tick, from the same playcut window, as the
        // `wxyc.playcuts` batch — the C6 artist-donation wiring the review
        // found had no production caller.
        let playcutIndexer = MockSpotlightIndexer()
        let artistIndexer = MockArtistSpotlightIndexer()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: playcutIndexer,
            artistIndexer: artistIndexer
        )

        await service.donateBatch(from: [
            .stub(id: 1, chronOrderID: 10, artistName: "Stereolab"),
            .stub(id: 2, chronOrderID: 20, artistName: "Juana Molina"),
        ])

        let playcutCall = try #require(await playcutIndexer.calls.first)
        #expect(playcutCall.entityIDs == [PlaycutID(1), PlaycutID(2)])

        let artistCall = try #require(await artistIndexer.calls.first)
        #expect(artistCall.entities.count == 2)
        #expect(artistCall.priority == SpotlightDonationService.batchPriority)
    }

    @Test("donateBatch is a no-op on an empty playlist")
    func donateBatchSkipsWhenEmpty() async {
        let playcutIndexer = MockSpotlightIndexer()
        let artistIndexer = MockArtistSpotlightIndexer()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: playcutIndexer,
            artistIndexer: artistIndexer
        )

        await service.donateBatch(from: [])

        #expect(await playcutIndexer.calls.isEmpty)
        #expect(await artistIndexer.calls.isEmpty)
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

    // MARK: - Metadata enrichment re-donation (issue #443)

    @Test("handleMetadataEnrichment re-donates a row previously donated by the batch path")
    func reDonatesPreviouslyBatchDonatedRow() async {
        let defaults = InMemoryDefaults()
        defaults.set("100", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        let enriched = Playcut.stub(
            id: 1,
            chronOrderID: 50,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            metadataStatus: .enrichedMatch
        )
        await service.handleMetadataEnrichment(for: enriched)

        let calls = await indexer.calls
        #expect(calls.count == 1)
        #expect(calls.first?.entityIDs == [PlaycutID(1)])
    }

    @Test("handleMetadataEnrichment re-donates the current on-air playcut even below the batch watermark")
    func reDonatesCurrentPlaycutBelowWatermark() async {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        // The per-tick path donates ahead of the batch path advancing the
        // watermark, so a row can be "previously donated" without being at
        // or below the watermark.
        await service.donateCurrentPlaycut(.stub(id: 1, chronOrderID: 999, metadataStatus: .pending))

        let enriched = Playcut.stub(
            id: 1,
            chronOrderID: 999,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            metadataStatus: .enrichedMatch
        )
        await service.handleMetadataEnrichment(for: enriched)

        // One call from donateCurrentPlaycut, one from the re-donation.
        #expect(await indexer.calls.count == 2)
    }

    @Test("handleMetadataEnrichment is a no-op for a row that was never donated")
    func skipsRowNeverDonated() async {
        let defaults = InMemoryDefaults()
        defaults.set("10", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        // chronOrderID 999 is above the watermark, and this instance never
        // donated it via the per-tick path either.
        let enriched = Playcut.stub(id: 1, chronOrderID: 999, metadataStatus: .enrichedMatch)
        await service.handleMetadataEnrichment(for: enriched)

        #expect(await indexer.calls.isEmpty)
    }

    @Test("handleMetadataEnrichment re-donates at batch priority, not elevated")
    func reDonatesAtBatchPriority() async throws {
        let defaults = InMemoryDefaults()
        defaults.set("100", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        await service.handleMetadataEnrichment(for: .stub(id: 1, chronOrderID: 50, metadataStatus: .enrichedMatch))

        let call = try #require(await indexer.calls.first)
        #expect(call.priority == SpotlightDonationService.batchPriority)
    }

    @Test("observeMetadataEnrichment re-donates exactly once for a terminal transition on a donated row")
    func observeReDonatesExactlyOnceForDonatedRow() async {
        let defaults = InMemoryDefaults()
        defaults.set("100", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        let enriched = Playcut.stub(
            id: 1,
            chronOrderID: 50,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            metadataStatus: .enrichedMatch
        )
        let source = MockPlaylistService(transitions: [enriched])

        await service.observeMetadataEnrichment(from: source)

        let calls = await indexer.calls
        #expect(calls.count == 1)
        #expect(calls.first?.entityIDs == [PlaycutID(1)])
    }

    @Test("handleMetadataEnrichment does not double-donate the entity the per-tick path just sent")
    func doesNotDoubleDonateCurrentPlaycutThisCycle() async {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        // On the tick its enrichment lands, the on-air playcut changes fields,
        // so the per-tick path (donateCurrentPlaycut) upserts the enriched
        // entity. The enrichment path then sees the same landing for the same
        // entity — re-donating it would burn a redundant XPC round-trip.
        let enriched = Playcut.stub(
            id: 1,
            chronOrderID: 999,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            metadataStatus: .enrichedMatch
        )

        await service.donateCurrentPlaycut(enriched)
        await service.handleMetadataEnrichment(for: enriched)

        #expect(await indexer.calls.count == 1)
    }

    @Test("A per-tick donation dedups against an enrichment re-donation of the same on-air entity")
    func perTickDedupsAgainstEnrichmentReDonation() async {
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: InMemoryDefaults(), indexer: indexer)

        // The two donation tasks race on the same actor with nondeterministic
        // ordering. Here the enrichment path wins: it re-donates the enriched
        // on-air entity before the per-tick path yields it. The per-tick path
        // must then dedup against that donation rather than sending a third
        // round-trip for the identical entity.
        let pending = Playcut.stub(id: 1, chronOrderID: 999, metadataStatus: .pending)
        await service.donateCurrentPlaycut(pending)

        let enriched = Playcut.stub(
            id: 1,
            chronOrderID: 999,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            metadataStatus: .enrichedMatch
        )
        await service.handleMetadataEnrichment(for: enriched)
        await service.donateCurrentPlaycut(enriched)

        // 1: per-tick pending. 2: enrichment re-donation. The trailing per-tick
        // call for the identical enriched entity dedups — no third call.
        #expect(await indexer.calls.count == 2)
    }

    @Test("observeMetadataEnrichment does not donate a terminal transition on an undonated row")
    func observeSkipsUndonatedRow() async {
        let defaults = InMemoryDefaults()
        defaults.set("100", forKey: SpotlightDonationService.watermarkKey)
        let indexer = MockSpotlightIndexer()
        let service = SpotlightDonationService(storage: defaults, indexer: indexer)

        let neverDonated = Playcut.stub(id: 2, chronOrderID: 999, metadataStatus: .enrichedMatch)
        let source = MockPlaylistService(transitions: [neverDonated])

        await service.observeMetadataEnrichment(from: source)

        #expect(await indexer.calls.isEmpty)
    }

    // MARK: - Donation analytics (#445)

    @Test("donateRecentPlaycuts emits SpotlightDonated with the newest row's playcut id, batch size, and batch priority")
    func recentBatchEmitsSpotlightDonated() async throws {
        let analytics = MockStructuredAnalytics()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            analytics: analytics
        )

        // Distinct id/chronOrderID values so the assertion below can't pass
        // by accident if `playcutID` were mistakenly populated from
        // chronOrderID (that value drives the watermark, not this event).
        await service.donateRecentPlaycuts([
            .stub(id: 5, chronOrderID: 10),
            .stub(id: 9, chronOrderID: 30),
        ])

        let events = analytics.typedEvents(ofType: SpotlightDonated.self)
        #expect(events.count == 1)
        #expect(events.first?.playcutID == "9")
        #expect(events.first?.batchSize == 2)
        #expect(events.first?.priorityTier == SpotlightDonationService.batchPriority)
    }

    @Test("donateRecentPlaycuts emits SpotlightDonationFailed, not SpotlightDonated, when the indexer throws")
    func recentBatchEmitsSpotlightDonationFailed() async throws {
        let analytics = MockStructuredAnalytics()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(shouldThrow: true),
            analytics: analytics
        )

        await service.donateRecentPlaycuts([.stub(id: 1, chronOrderID: 10)])

        #expect(analytics.typedEvents(ofType: SpotlightDonated.self).isEmpty)
        let failures = analytics.typedEvents(ofType: SpotlightDonationFailed.self)
        #expect(failures.count == 1)
        #expect(failures.first?.batchSize == 1)
        #expect(failures.first?.errorKind == "MockSpotlightIndexer")
    }

    @Test("donateRecentPlaycuts emits nothing when every playcut is stale")
    func recentBatchEmitsNothingWhenAllStale() async {
        let defaults = InMemoryDefaults()
        defaults.set("100", forKey: SpotlightDonationService.watermarkKey)
        let analytics = MockStructuredAnalytics()
        let service = SpotlightDonationService(
            storage: defaults,
            indexer: MockSpotlightIndexer(),
            analytics: analytics
        )

        await service.donateRecentPlaycuts([.stub(id: 1, chronOrderID: 10)])

        #expect(analytics.events.isEmpty)
    }

    @Test("donateArtists emits SpotlightDonated with the deduped entity count and batch priority")
    func donateArtistsEmitsSpotlightDonated() async throws {
        let analytics = MockStructuredAnalytics()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: MockArtistSpotlightIndexer(),
            analytics: analytics
        )

        // Distinct id/chronOrderID values so the assertion below can't pass
        // by accident if `playcutID` were mistakenly populated from
        // chronOrderID instead of the playcut's own `.id`.
        await service.donateArtists(from: [
            .stub(id: 7, chronOrderID: 10, artistName: "Stereolab"),
            .stub(id: 11, chronOrderID: 20, artistName: "Juana Molina"),
        ])

        let events = analytics.typedEvents(ofType: SpotlightDonated.self)
        #expect(events.count == 1)
        #expect(events.first?.batchSize == 2)
        #expect(events.first?.priorityTier == SpotlightDonationService.batchPriority)
        // Representative id is the `.id` of the input playcut with the
        // highest chronOrderID.
        #expect(events.first?.playcutID == "11")
    }

    @Test("donateArtists emits SpotlightDonationFailed when the artist indexer throws")
    func donateArtistsEmitsSpotlightDonationFailed() async throws {
        let analytics = MockStructuredAnalytics()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: MockArtistSpotlightIndexer(shouldThrow: true),
            analytics: analytics
        )

        await service.donateArtists(from: [.stub(id: 1, artistName: "Stereolab")])

        #expect(analytics.typedEvents(ofType: SpotlightDonated.self).isEmpty)
        let failures = analytics.typedEvents(ofType: SpotlightDonationFailed.self)
        #expect(failures.count == 1)
        #expect(failures.first?.batchSize == 1)
        #expect(failures.first?.errorKind == "MockArtistSpotlightIndexer")
    }

    @Test("donateArtists emits nothing on an empty playlist")
    func donateArtistsEmitsNothingWhenEmpty() async {
        let analytics = MockStructuredAnalytics()
        let service = SpotlightDonationService(
            storage: InMemoryDefaults(),
            indexer: MockSpotlightIndexer(),
            artistIndexer: MockArtistSpotlightIndexer(),
            analytics: analytics
        )

        await service.donateArtists(from: [])

        #expect(analytics.events.isEmpty)
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

/// Records `indexArtists` calls for `donateArtists(from:)` assertions (C6).
actor MockArtistSpotlightIndexer: ArtistSpotlightIndexer {
    struct Call: Sendable {
        let entities: [ArtistEntity]
        let priority: Int
    }

    private(set) var calls: [Call] = []
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func indexArtists(_ entities: [ArtistEntity], priority: Int) async throws {
        calls.append(Call(entities: entities, priority: priority))
        if shouldThrow {
            throw NSError(domain: "MockArtistSpotlightIndexer", code: 1)
        }
    }
}

/// Stand-in for a live `PlaylistService` in `observeMetadataEnrichment(from:)`
/// tests. Yields a fixed, pre-filtered sequence of terminal-transition
/// playcuts — the diffing behavior that produces such a sequence from raw
/// playlist ticks is `PlaylistService`'s own contract, covered by
/// `PlaylistServiceMetadataTransitionsTests` in the `Playlist` package.
struct MockPlaylistService: MetadataEnrichmentTransitionsSource {
    let transitions: [Playcut]

    func terminalMetadataTransitions() -> AsyncStream<Playcut> {
        AsyncStream { continuation in
            for playcut in transitions {
                continuation.yield(playcut)
            }
            continuation.finish()
        }
    }
}
#endif
