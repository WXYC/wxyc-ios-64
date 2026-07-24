//
//  VenueEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies VenueEntityQuery's identifier-lookup path and the safe empty
//  defaults used by the F4 slice, mirroring ConcertEntityQueryTests.
//  Includes an order-preservation guarantee so a source that resolves ids
//  out of order (dict lookup, DB query) still hands entities back in the
//  caller's order per the AppIntents contract.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Concerts
import ConcertsTesting
@testable import WXYCIntents

@Suite("VenueEntityQuery")
struct VenueEntityQueryTests {
    @Test("resolves identifiers via the injected source")
    func entitiesForIdentifiersUsesSource() async throws {
        let catsCradle = Venue.stub(id: 1, name: "Cat's Cradle")
        let motorco = Venue.stub(id: 2, name: "Motorco Music Hall")
        let source: VenueEntityQuery.VenueSource = { ids in
            [catsCradle, motorco].filter { ids.contains($0.id) }
        }
        let query = VenueEntityQuery(source: source)

        let catsCradleID = try #require(VenueID(venueID: 1))
        let motorcoID = try #require(VenueID(venueID: 2))
        let entities = try await query.entities(for: [catsCradleID, motorcoID])

        #expect(entities.map(\.id) == [catsCradleID, motorcoID])
    }

    @Test("preserves the caller's identifier order even when the source returns them re-ordered")
    func entitiesForIdentifiersPreservesOrder() async throws {
        let catsCradle = Venue.stub(id: 1, name: "Cat's Cradle")
        let motorco = Venue.stub(id: 2, name: "Motorco Music Hall")
        // Source deliberately returns 2 before 1 to force the query's
        // dict-then-order-by-input path to do real work.
        let source: VenueEntityQuery.VenueSource = { _ in [motorco, catsCradle] }
        let query = VenueEntityQuery(source: source)

        let catsCradleID = try #require(VenueID(venueID: 1))
        let motorcoID = try #require(VenueID(venueID: 2))
        let entities = try await query.entities(for: [catsCradleID, motorcoID])

        #expect(entities.map(\.id) == [catsCradleID, motorcoID])
    }

    @Test("returns only the entities the source supplies")
    func entitiesForIdentifiersDropsUnknownIDs() async throws {
        let catsCradle = Venue.stub(id: 1, name: "Cat's Cradle")
        let source: VenueEntityQuery.VenueSource = { ids in
            [catsCradle].filter { ids.contains($0.id) }
        }
        let query = VenueEntityQuery(source: source)

        let catsCradleID = try #require(VenueID(venueID: 1))
        let unknownID = try #require(VenueID(venueID: 999))
        let entities = try await query.entities(for: [catsCradleID, unknownID])

        #expect(entities.map(\.id) == [catsCradleID])
    }

    @Test("default source returns no entities")
    func defaultSourceReturnsEmpty() async throws {
        let query = VenueEntityQuery()

        let ids = try [1, 2, 3].map { try #require(VenueID(venueID: $0)) }
        let entities = try await query.entities(for: ids)

        #expect(entities.isEmpty)
    }

    @Test("suggestedEntities returns [] in the F4 slice")
    func suggestedEntitiesEmpty() async throws {
        let query = VenueEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }
}
