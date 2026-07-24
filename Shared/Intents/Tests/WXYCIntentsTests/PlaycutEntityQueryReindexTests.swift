//
//  PlaycutEntityQueryReindexTests.swift
//  WXYCIntents
//
//  Verifies the F3 `IndexedEntityQuery` reindex handlers via a spy
//  `PlaycutReindexer`: `reindexEntities(for:)` donates only ids the seeded
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
//  `.serialized`: `AppDependencyManager.shared` is a process-global registry
//  keyed by dependency type, shared with `PlaycutEntityQueryTests`'
//  production-binding tests. Parallel registration of different
//  `PlaycutHistoryStore`/`PlaycutReindexer` instances across suites could
//  race on which one a given test's `entities`/`reindex*` calls resolve.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import AppIntents
import Caching
import CoreSpotlight
import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("PlaycutEntityQuery+IndexedEntityQuery (F3 reindex handlers)", .serialized)
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
        AppDependencyManager.shared.add(dependency: reindexer as any PlaycutReindexer)

        let query = PlaycutEntityQuery()
        try await query.reindexEntities(
            for: [PlaycutID(1), PlaycutID(999)],
            indexDescription: CSSearchableIndexDescription()
        )

        let donated = await reindexer.donatedIDs
        #expect(donated == [PlaycutID(1)])
    }

    @Test("reindexEntities with no matches in the store donates nothing")
    func reindexEntitiesEmptyMatchDonatesNothing() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        AppDependencyManager.shared.add(dependency: PlaycutEntityQueryTests.makeHistoryStore())
        let reindexer = SpyPlaycutReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any PlaycutReindexer)

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
        AppDependencyManager.shared.add(dependency: reindexer as any PlaycutReindexer)

        let query = PlaycutEntityQuery()
        try await query.reindexAllEntities(indexDescription: CSSearchableIndexDescription())

        let batches = await reindexer.donatedBatches
        #expect(batches.map(\.count) == [50, 50, 20])
        #expect(batches.allSatisfy { $0.count <= 50 })
        #expect(Set(batches.flatMap { $0 }) == Set(playcuts.map { PlaycutID($0.id) }))
    }

    @Test("reindexAllEntities against an empty store donates nothing")
    func reindexAllEntitiesEmptyStoreDonatesNothing() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        AppDependencyManager.shared.add(dependency: PlaycutEntityQueryTests.makeHistoryStore())
        let reindexer = SpyPlaycutReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any PlaycutReindexer)

        let query = PlaycutEntityQuery()
        try await query.reindexAllEntities(indexDescription: CSSearchableIndexDescription())

        let batches = await reindexer.donatedBatches
        #expect(batches.isEmpty)
    }
}

/// Records every `donate(_:)` call's entity ids as a separate batch, so tests
/// can assert both chunk boundaries and total membership.
actor SpyPlaycutReindexer: PlaycutReindexer {
    private(set) var donatedBatches: [[PlaycutID]] = []

    var donatedIDs: [PlaycutID] {
        donatedBatches.flatMap { $0 }
    }

    func donate(_ entities: [PlaycutEntity]) async throws {
        donatedBatches.append(entities.map(\.id))
    }
}
#endif
