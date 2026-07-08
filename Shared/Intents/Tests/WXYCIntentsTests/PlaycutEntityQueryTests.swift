//
//  PlaycutEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies PlaycutEntityQuery's identifier-lookup path and the safe empty
//  defaults used by the F1 slice. Includes an order-preservation guarantee so
//  a source that resolves ids out of order (dict lookup, DB query) still
//  hands entities back in the caller's order per the AppIntents contract.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

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

    @Test("default source returns no entities")
    func defaultSourceReturnsEmpty() async throws {
        let query = PlaycutEntityQuery()

        let entities = try await query.entities(for: [PlaycutID(1), PlaycutID(2), PlaycutID(3)])

        #expect(entities.isEmpty)
    }

    @Test("suggestedEntities returns [] in the F1 slice")
    func suggestedEntitiesEmpty() async throws {
        let query = PlaycutEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }
}
