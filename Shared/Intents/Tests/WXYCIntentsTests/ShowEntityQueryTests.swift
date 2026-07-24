//
//  ShowEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies ShowEntityQuery's identifier-lookup path and the safe empty
//  defaults, mirroring PlaycutEntityQueryTests.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("ShowEntityQuery")
struct ShowEntityQueryTests {
    @Test("resolves identifiers via the injected source")
    func entitiesForIdentifiersUsesSource() async throws {
        let jake = ShowMarker.stub(id: 1, djName: "Jake B")
        let dee = ShowMarker.stub(id: 2, djName: "Dee Jay")
        let source: ShowEntityQuery.ShowSource = { ids in
            [jake, dee].filter { ids.contains($0.id) }
        }
        let query = ShowEntityQuery(source: source)

        let entities = try await query.entities(for: [ShowID(1), ShowID(2)])

        #expect(entities.map(\.id) == [ShowID(1), ShowID(2)])
    }

    @Test("preserves the caller's identifier order even when the source returns them re-ordered")
    func entitiesForIdentifiersPreservesOrder() async throws {
        let jake = ShowMarker.stub(id: 1, djName: "Jake B")
        let dee = ShowMarker.stub(id: 2, djName: "Dee Jay")
        let source: ShowEntityQuery.ShowSource = { _ in [dee, jake] }
        let query = ShowEntityQuery(source: source)

        let entities = try await query.entities(for: [ShowID(1), ShowID(2)])

        #expect(entities.map(\.id) == [ShowID(1), ShowID(2)])
    }

    @Test("returns only the entities the source supplies")
    func entitiesForIdentifiersDropsUnknownIDs() async throws {
        let jake = ShowMarker.stub(id: 1, djName: "Jake B")
        let source: ShowEntityQuery.ShowSource = { ids in
            [jake].filter { ids.contains($0.id) }
        }
        let query = ShowEntityQuery(source: source)

        let entities = try await query.entities(for: [ShowID(1), ShowID(999)])

        #expect(entities.map(\.id) == [ShowID(1)])
    }

    @Test("default source returns no entities")
    func defaultSourceReturnsEmpty() async throws {
        let query = ShowEntityQuery()

        let entities = try await query.entities(for: [ShowID(1), ShowID(2), ShowID(3)])

        #expect(entities.isEmpty)
    }

    @Test("suggestedEntities returns [] in this slice")
    func suggestedEntitiesEmpty() async throws {
        let query = ShowEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }
}
