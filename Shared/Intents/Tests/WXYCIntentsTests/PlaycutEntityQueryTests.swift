//
//  PlaycutEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies PlaycutEntityQuery's identifier-lookup path and the safe empty defaults
//  used by the F1 slice — reindex handlers and suggestion sources land later.
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

        #expect(entities.count == 2)
        #expect(Set(entities.map(\.id)) == [PlaycutID(1), PlaycutID(2)])
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
