//
//  LabelEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies LabelEntityQuery's identifier-lookup path: the injected playcut
//  source is deduped by normalized label name (dropping playcuts with no
//  `labelName`) before resolving the caller's requested ids, and the safe
//  empty defaults used by the F5d slice.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("LabelEntityQuery")
struct LabelEntityQueryTests {
    @Test("dedups playcuts with label-name casing/whitespace variations to a single resolvable entity")
    func entitiesForIdentifiersDedupsLabelVariations() async throws {
        let sonamos = Playcut.stub(id: 1, labelName: "Sonamos", artistName: "Juana Molina")
        let sonamosMessy = Playcut.stub(id: 2, labelName: "  sonamos  ", artistName: "Stereolab")
        let query = LabelEntityQuery(source: { [sonamos, sonamosMessy] })
        let wantedID = LabelEntity(labelName: "Sonamos").id

        let entities = try await query.entities(for: [wantedID])

        #expect(entities.count == 1)
        #expect(entities.first?.normalizedName == "sonamos")
    }

    @Test("skips playcuts with no labelName")
    func entitiesForIdentifiersSkipsPlaycutsWithNoLabel() async throws {
        let noLabel = Playcut.stub(id: 1, labelName: nil, artistName: "Cat Power")
        let dragCity = Playcut.stub(id: 2, labelName: "Drag City", artistName: "Jessica Pratt")
        let query = LabelEntityQuery(source: { [noLabel, dragCity] })
        let dragCityID = LabelEntity(labelName: "Drag City").id

        let entities = try await query.entities(for: [dragCityID])

        #expect(entities.count == 1)
        #expect(entities.first?.normalizedName == "drag city")
    }

    @Test("returns only the entities the source can resolve")
    func entitiesForIdentifiersDropsUnknownIDs() async throws {
        let dragCity = Playcut.stub(id: 1, labelName: "Drag City", artistName: "Jessica Pratt")
        let query = LabelEntityQuery(source: { [dragCity] })
        let unknownID = LabelEntity(labelName: "Merge Records").id

        let entities = try await query.entities(for: [unknownID])

        #expect(entities.isEmpty)
    }

    @Test("default source returns no entities")
    func defaultSourceReturnsEmpty() async throws {
        let query = LabelEntityQuery()
        let anyID = LabelEntity(labelName: "Drag City").id

        let entities = try await query.entities(for: [anyID])

        #expect(entities.isEmpty)
    }

    @Test("suggestedEntities returns [] in the F5d slice")
    func suggestedEntitiesEmpty() async throws {
        let query = LabelEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }
}
