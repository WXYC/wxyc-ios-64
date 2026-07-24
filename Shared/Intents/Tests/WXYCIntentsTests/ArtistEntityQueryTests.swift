//
//  ArtistEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies ArtistEntityQuery's identifier-lookup path: the injected playcut
//  source is deduped by normalized artist name before resolving the caller's
//  requested ids, and the safe empty defaults used by the F5b slice.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("ArtistEntityQuery")
struct ArtistEntityQueryTests {
    @Test("dedups playcuts with name variations to a single resolvable entity")
    func entitiesForIdentifiersDedupsNameVariations() async throws {
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab")
        let stereolabFeaturing = Playcut.stub(id: 2, artistName: "Stereolab feat. Nurse With Wound")
        let query = ArtistEntityQuery(source: { [stereolab, stereolabFeaturing] })
        let wantedID = ArtistEntity(artistName: "Stereolab").id

        let entities = try await query.entities(for: [wantedID])

        #expect(entities.count == 1)
        #expect(entities.first?.normalizedName == "stereolab")
    }

    @Test("returns only the entities the source can resolve")
    func entitiesForIdentifiersDropsUnknownIDs() async throws {
        let juana = Playcut.stub(id: 1, artistName: "Juana Molina")
        let query = ArtistEntityQuery(source: { [juana] })
        let unknownID = ArtistEntity(artistName: "Cat Power").id

        let entities = try await query.entities(for: [unknownID])

        #expect(entities.isEmpty)
    }

    @Test("default source returns no entities")
    func defaultSourceReturnsEmpty() async throws {
        let query = ArtistEntityQuery()
        let anyID = ArtistEntity(artistName: "Juana Molina").id

        let entities = try await query.entities(for: [anyID])

        #expect(entities.isEmpty)
    }

    @Test("suggestedEntities returns [] in the F5b slice")
    func suggestedEntitiesEmpty() async throws {
        let query = ArtistEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }
}
