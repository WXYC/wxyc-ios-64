//
//  ConcertEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies ConcertEntityQuery's identifier-lookup path and the safe empty
//  defaults used by the F1 slice, mirroring PlaycutEntityQueryTests /
//  ShowEntityQueryTests. Includes an order-preservation guarantee so a source
//  that resolves ids out of order (dict lookup, DB query) still hands
//  entities back in the caller's order per the AppIntents contract.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Concerts
import ConcertsTesting
@testable import WXYCIntents

@Suite("ConcertEntityQuery")
struct ConcertEntityQueryTests {
    @Test("resolves identifiers via the injected source")
    func entitiesForIdentifiersUsesSource() async throws {
        let jessica = Concert.stub(id: 1, headliningArtistRaw: "Jessica Pratt")
        let juana = Concert.stub(id: 2, headliningArtistRaw: "Juana Molina")
        let source: ConcertEntityQuery.ConcertSource = { ids in
            [jessica, juana].filter { ids.contains($0.id) }
        }
        let query = ConcertEntityQuery(source: source)

        let jessicaID = try #require(ConcertID(concertID: 1))
        let juanaID = try #require(ConcertID(concertID: 2))
        let entities = try await query.entities(for: [jessicaID, juanaID])

        #expect(entities.map(\.id) == [jessicaID, juanaID])
    }

    @Test("preserves the caller's identifier order even when the source returns them re-ordered")
    func entitiesForIdentifiersPreservesOrder() async throws {
        let jessica = Concert.stub(id: 1, headliningArtistRaw: "Jessica Pratt")
        let juana = Concert.stub(id: 2, headliningArtistRaw: "Juana Molina")
        // Source deliberately returns 2 before 1 to force the query's
        // dict-then-order-by-input path to do real work.
        let source: ConcertEntityQuery.ConcertSource = { _ in [juana, jessica] }
        let query = ConcertEntityQuery(source: source)

        let jessicaID = try #require(ConcertID(concertID: 1))
        let juanaID = try #require(ConcertID(concertID: 2))
        let entities = try await query.entities(for: [jessicaID, juanaID])

        #expect(entities.map(\.id) == [jessicaID, juanaID])
    }

    @Test("returns only the entities the source supplies")
    func entitiesForIdentifiersDropsUnknownIDs() async throws {
        let jessica = Concert.stub(id: 1, headliningArtistRaw: "Jessica Pratt")
        let source: ConcertEntityQuery.ConcertSource = { ids in
            [jessica].filter { ids.contains($0.id) }
        }
        let query = ConcertEntityQuery(source: source)

        let jessicaID = try #require(ConcertID(concertID: 1))
        let unknownID = try #require(ConcertID(concertID: 999))
        let entities = try await query.entities(for: [jessicaID, unknownID])

        #expect(entities.map(\.id) == [jessicaID])
    }

    @Test("default source returns no entities")
    func defaultSourceReturnsEmpty() async throws {
        let query = ConcertEntityQuery()

        let ids = try [1, 2, 3].map { try #require(ConcertID(concertID: $0)) }
        let entities = try await query.entities(for: ids)

        #expect(entities.isEmpty)
    }

    @Test("suggestedEntities returns [] in the F1 slice")
    func suggestedEntitiesEmpty() async throws {
        let query = ConcertEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }
}
