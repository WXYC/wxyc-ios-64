//
//  DJEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies DJEntityQuery's identifier-lookup path: the injected show-marker
//  source is deduped by normalized DJ name before resolving the caller's
//  requested ids, markers with no DJ name are skipped, and the safe empty
//  defaults used by the F5b slice, mirroring ArtistEntityQueryTests.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("DJEntityQuery")
struct DJEntityQueryTests {
    @Test("dedups show markers with case/whitespace name variations to a single resolvable entity")
    func entitiesForIdentifiersDedupsNameVariations() async throws {
        let jake = ShowMarker.stub(id: 1, djName: "Jake B")
        let jakeMessy = ShowMarker.stub(id: 2, djName: "  jake   b  ")
        let query = DJEntityQuery(source: { [jake, jakeMessy] })
        let wantedID = DJEntity(djName: "Jake B").id

        let entities = try await query.entities(for: [wantedID])

        #expect(entities.count == 1)
        #expect(entities.first?.normalizedName == "jake b")
    }

    @Test("skips show markers with no DJ name")
    func entitiesForIdentifiersSkipsMarkersWithNoDJName() async throws {
        let unnamed = ShowMarker.stub(id: 1, djName: nil)
        let jake = ShowMarker.stub(id: 2, djName: "Jake B")
        let query = DJEntityQuery(source: { [unnamed, jake] })
        let wantedID = DJEntity(djName: "Jake B").id

        let entities = try await query.entities(for: [wantedID])

        #expect(entities.count == 1)
        #expect(entities.first?.normalizedName == "jake b")
    }

    @Test("returns only the entities the source can resolve")
    func entitiesForIdentifiersDropsUnknownIDs() async throws {
        let jake = ShowMarker.stub(id: 1, djName: "Jake B")
        let query = DJEntityQuery(source: { [jake] })
        let unknownID = DJEntity(djName: "DJ Rembert").id

        let entities = try await query.entities(for: [unknownID])

        #expect(entities.isEmpty)
    }

    @Test("default source returns no entities")
    func defaultSourceReturnsEmpty() async throws {
        let query = DJEntityQuery()
        let anyID = DJEntity(djName: "Jake B").id

        let entities = try await query.entities(for: [anyID])

        #expect(entities.isEmpty)
    }

    @Test("suggestedEntities returns [] in the F5b slice")
    func suggestedEntitiesEmpty() async throws {
        let query = DJEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }
}
