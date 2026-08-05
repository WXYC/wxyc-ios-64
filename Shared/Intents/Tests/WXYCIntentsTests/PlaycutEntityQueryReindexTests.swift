//
//  PlaycutEntityQueryReindexTests.swift
//  WXYCIntents
//
//  Verifies the F3 `IndexedEntityQuery` reindex handlers via a spy
//  `SpotlightReindexer<PlaycutEntity>`: `reindexEntities(for:)` donates only ids the seeded
//  `PlaycutHistoryStore` actually has (a miss is omitted, not an error), and
//  `reindexAllEntities` donates the store's full indexable set in
//  ≤50-entity chunks.
//
//  Gated to Swift 6.4 (the Xcode 27 beta toolchain), matching
//  `PlaycutEntityQuery+IndexedEntityQuery.swift`. Each test starts with
//  `guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }`
//  (the `PlayWXYCAudioTests.swift` precedent) so the suite is a no-op rather
//  than a failure on a host OS below the runtime floor — the beta-toolchain
//  verification for this ticket is a build, not a test run.
//
//  Nested under `ReindexHandlerTests` (`ReindexHandlerTests.swift`) rather than
//  carrying its own top-level `.serialized` trait: `AppDependencyManager.shared`
//  is a process-global registry keyed by dependency type, and this suite's
//  sibling `ConcertEntityQueryReindexTests` registers the same `any
//  AnalyticsService` type. A suite-local `.serialized` only serializes a
//  suite's own tests against each other — it does nothing to stop Swift
//  Testing's default parallel scheduler from running a test from this suite
//  concurrently with one from the concert suite, which could race on
//  `AppDependencyManager.shared`'s registration. `.serialized` on the shared
//  parent suite governs both children together, closing that gap. (Parallel
//  registration of different `PlaycutHistoryStore`/`SpotlightReindexer<PlaycutEntity>`
//  instances against `PlaycutEntityQueryTests`' production-binding tests is a
//  separate, pre-existing risk this file does not address.)
//
//  Every test also registers a `MockStructuredAnalytics` — `PlaycutEntityQuery`'s
//  `analytics` property (#445) is a required `@Dependency`, which traps on
//  access if unregistered.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import Analytics
import AnalyticsTesting
import AppIntents
import Caching
import CoreSpotlight
import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

extension ReindexHandlerTests {

@Suite("PlaycutEntityQuery+IndexedEntityQuery (F3 reindex handlers)")
struct PlaycutEntityQueryReindexTests {
    @Test("reindexEntities donates only ids present in the store; a miss is omitted, not an error")
    func reindexEntitiesDonatesOnlyKnownIDs() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let store = PlaycutEntityQueryTests.makeHistoryStore()
        await store.ingest([
            .stub(id: 1, hour: PlaycutEntityQueryTests.recentHourMS, artistName: "Juana Molina"),
            .stub(id: 2, hour: PlaycutEntityQueryTests.recentHourMS, artistName: "Stereolab"),
        ])
        AppDependencyManager.shared.add(dependency: store)
        let reindexer = SpyPlaycutReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any SpotlightReindexer<PlaycutEntity>)
        let analytics = MockStructuredAnalytics()
        AppDependencyManager.shared.add(dependency: analytics as any AnalyticsService)

        let query = PlaycutEntityQuery()
        try await query.reindexEntities(
            for: [PlaycutID(1), PlaycutID(999)],
            indexDescription: CSSearchableIndexDescription()
        )

        let donated = await reindexer.donatedIDs
        #expect(donated == [PlaycutID(1)])

        // #445: reports the request count (both ids asked for), not just the
        // ids the store resolved.
        let events = analytics.typedEvents(ofType: SpotlightReindexRequested.self)
        #expect(events.count == 1)
        #expect(events.first?.kind == "single")
        #expect(events.first?.rowCount == 2)
    }

    @Test("reindexEntities with no matches in the store donates nothing")
    func reindexEntitiesEmptyMatchDonatesNothing() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        AppDependencyManager.shared.add(dependency: PlaycutEntityQueryTests.makeHistoryStore())
        let reindexer = SpyPlaycutReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any SpotlightReindexer<PlaycutEntity>)
        AppDependencyManager.shared.add(dependency: MockStructuredAnalytics() as any AnalyticsService)

        let query = PlaycutEntityQuery()
        try await query.reindexEntities(for: [PlaycutID(404)], indexDescription: CSSearchableIndexDescription())

        let batches = await reindexer.donatedBatches
        #expect(batches.isEmpty)
    }

    @Test("reindexAllEntities donates the full indexable set in chunks of at most 50")
    func reindexAllEntitiesChunks() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let store = PlaycutEntityQueryTests.makeHistoryStore()
        let recent = PlaycutEntityQueryTests.recentHourMS
        // 120 rows: exercises two full 50-entity chunks plus a 20-row remainder.
        let playcuts = (1...120).map { id in
            Playcut.stub(id: UInt64(id), hour: recent, chronOrderID: UInt64(id), artistName: "Juana Molina")
        }
        await store.ingest(playcuts)
        AppDependencyManager.shared.add(dependency: store)
        let reindexer = SpyPlaycutReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any SpotlightReindexer<PlaycutEntity>)
        let analytics = MockStructuredAnalytics()
        AppDependencyManager.shared.add(dependency: analytics as any AnalyticsService)

        let query = PlaycutEntityQuery()
        try await query.reindexAllEntities(indexDescription: CSSearchableIndexDescription())

        let batches = await reindexer.donatedBatches
        #expect(batches.map(\.count) == [50, 50, 20])
        #expect(batches.allSatisfy { $0.count <= 50 })
        #expect(Set(batches.flatMap { $0 }) == Set(playcuts.map { PlaycutID($0.id) }))

        let events = analytics.typedEvents(ofType: SpotlightReindexRequested.self)
        #expect(events.count == 1)
        #expect(events.first?.kind == "all")
        #expect(events.first?.rowCount == 120)
    }

    @Test("reindexAllEntities against an empty store donates nothing")
    func reindexAllEntitiesEmptyStoreDonatesNothing() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        AppDependencyManager.shared.add(dependency: PlaycutEntityQueryTests.makeHistoryStore())
        let reindexer = SpyPlaycutReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any SpotlightReindexer<PlaycutEntity>)
        AppDependencyManager.shared.add(dependency: MockStructuredAnalytics() as any AnalyticsService)

        let query = PlaycutEntityQuery()
        try await query.reindexAllEntities(indexDescription: CSSearchableIndexDescription())

        let batches = await reindexer.donatedBatches
        #expect(batches.isEmpty)
    }
}

} // extension ReindexHandlerTests

/// Records every `donate(_:)` call's entity ids as a separate batch, so tests
/// can assert both chunk boundaries and total membership.
actor SpyPlaycutReindexer: SpotlightReindexer {
    private(set) var donatedBatches: [[PlaycutID]] = []

    var donatedIDs: [PlaycutID] {
        donatedBatches.flatMap { $0 }
    }

    func donate(_ entities: [PlaycutEntity]) async throws {
        donatedBatches.append(entities.map(\.id))
    }
}
#endif
