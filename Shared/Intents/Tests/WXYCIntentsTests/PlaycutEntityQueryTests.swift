//
//  PlaycutEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies PlaycutEntityQuery's identifier-lookup path: the closure-injected
//  seam tests use and, since F3, resolution through a real
//  `PlaycutHistoryStore`. Production `init()` resolves that store via
//  `@Dependency`, injected by the AppIntents runtime — a binding a bare test
//  process can't drive (there's no public API to force AppIntents dependency
//  resolution, and reading a `@Dependency` getter outside the runtime traps).
//  These tests wire the same store through the `init(source:)` seam that
//  `entities(for:)` reads when a source is present, exercising the identical
//  `PlaycutHistoryStore.playcuts(ids:)` → dedup/order path. Includes an
//  order-preservation guarantee so a source that resolves ids out of order
//  (dict lookup, DB query) still hands entities back in the caller's order
//  per the AppIntents contract.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("PlaycutEntityQuery")
struct PlaycutEntityQueryTests {
    @Test("resolves identifiers via the injected source")
    func entitiesForIdentifiersUsesSource() async throws {
        let juana = Playcut.stub(id: 1, songTitle: "la paradoja", artistName: "Juana Molina")
        let jessica = Playcut.stub(id: 2, songTitle: "Back, Baby", artistName: "Jessica Pratt")
        let source: PlaycutEntityQuery.PlaycutSource = { ids in
            [juana, jessica].filter { ids.contains($0.id) }
        }
        let query = PlaycutEntityQuery(source: source)

        let entities = try await query.entities(for: [PlaycutID(1), PlaycutID(2)])

        #expect(entities.map(\.id) == [PlaycutID(1), PlaycutID(2)])
    }

    @Test("preserves the caller's identifier order even when the source returns them re-ordered")
    func entitiesForIdentifiersPreservesOrder() async throws {
        let juana = Playcut.stub(id: 1, songTitle: "la paradoja", artistName: "Juana Molina")
        let jessica = Playcut.stub(id: 2, songTitle: "Back, Baby", artistName: "Jessica Pratt")
        // Source deliberately returns 2 before 1 to force the query's
        // dict-then-order-by-input path to do real work.
        let source: PlaycutEntityQuery.PlaycutSource = { _ in [jessica, juana] }
        let query = PlaycutEntityQuery(source: source)

        let entities = try await query.entities(for: [PlaycutID(1), PlaycutID(2)])

        #expect(entities.map(\.id) == [PlaycutID(1), PlaycutID(2)])
    }

    @Test("returns only the entities the source supplies")
    func entitiesForIdentifiersDropsUnknownIDs() async throws {
        let juana = Playcut.stub(id: 1)
        let source: PlaycutEntityQuery.PlaycutSource = { ids in
            [juana].filter { ids.contains($0.id) }
        }
        let query = PlaycutEntityQuery(source: source)

        let entities = try await query.entities(for: [PlaycutID(1), PlaycutID(999)])

        #expect(entities.map(\.id) == [PlaycutID(1)])
    }

    @Test("suggestedEntities returns [] in the F1 slice")
    func suggestedEntitiesEmpty() async throws {
        let query = PlaycutEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }

    // MARK: - F3: resolution through a real PlaycutHistoryStore

    @Test("resolves identifiers through a real PlaycutHistoryStore, preserving order and dropping unknown ids")
    func entitiesForIdentifiersResolvesThroughHistoryStore() async throws {
        let store = Self.makeHistoryStore()
        await store.ingest([
            .stub(id: 1, hour: Self.recentHourMS, songTitle: "la paradoja", artistName: "Juana Molina"),
            .stub(id: 2, hour: Self.recentHourMS, songTitle: "Aluminum Tunes", artistName: "Stereolab"),
        ])
        // The `init(source:)` seam stands in for the production `@Dependency`
        // binding, calling the same `PlaycutHistoryStore.playcuts(ids:)` the
        // no-source production path resolves through.
        let query = PlaycutEntityQuery(source: { await store.playcuts(ids: Set($0)) })
        // Deliberately out of ingest order and with an id the store never
        // saw, to exercise the order-preservation + drop-unknown-ids contract
        // against a real store.
        let entities = try await query.entities(for: [PlaycutID(2), PlaycutID(1), PlaycutID(999)])

        #expect(entities.map(\.id) == [PlaycutID(2), PlaycutID(1)])
    }

    @Test("a PlaycutHistoryStore resolving nothing yields no entities, not a trap")
    func entitiesForIdentifiersEmptyStoreYieldsNoEntities() async throws {
        let store = Self.makeHistoryStore()

        let query = PlaycutEntityQuery(source: { await store.playcuts(ids: Set($0)) })
        let entities = try await query.entities(for: [PlaycutID(1), PlaycutID(2)])

        #expect(entities.isEmpty)
    }

    /// A `PlaycutHistoryStore` backed by an isolated in-memory cache, so a
    /// test can never read or write the real `playcut-history` disk cache.
    static func makeHistoryStore() -> PlaycutHistoryStore {
        PlaycutHistoryStore(cacheCoordinator: CacheCoordinator(cache: InMemoryCache()))
    }

    /// "Now", in the `Playcut.hour` (milliseconds since epoch) domain, so
    /// seeded playcuts always land inside `PlaycutHistoryStore`'s rolling
    /// 90-day ingest window regardless of when the suite runs.
    static var recentHourMS: UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}
