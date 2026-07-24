//
//  ReleaseEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies ReleaseEntityQuery's identifier-lookup path: the injected playcut
//  source is deduped by the (artist, release) composite key before resolving
//  the caller's requested ids, and the safe empty defaults used by this slice.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("ReleaseEntityQuery")
struct ReleaseEntityQueryTests {
    @Test("dedups playcuts with artist-name variations to a single resolvable entity")
    func entitiesForIdentifiersDedupsNameVariations() async throws {
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab", releaseTitle: "Dots and Loops")
        let stereolabFeaturing = Playcut.stub(
            id: 2,
            artistName: "Stereolab feat. Nurse With Wound",
            releaseTitle: "Dots and Loops"
        )
        let query = ReleaseEntityQuery(source: { [stereolab, stereolabFeaturing] })
        let wantedID = ReleaseEntity(artistName: "Stereolab", releaseTitle: "Dots and Loops").id

        let entities = try await query.entities(for: [wantedID])

        #expect(entities.count == 1)
        #expect(entities.first?.normalizedReleaseTitle == "dots and loops")
    }

    @Test("returns only the entities the source can resolve")
    func entitiesForIdentifiersDropsUnknownIDs() async throws {
        let halo = Playcut.stub(id: 1, artistName: "Juana Molina", releaseTitle: "Halo")
        let query = ReleaseEntityQuery(source: { [halo] })
        let unknownID = ReleaseEntity(artistName: "Cat Power", releaseTitle: "Moon Pix").id

        let entities = try await query.entities(for: [unknownID])

        #expect(entities.isEmpty)
    }

    @Test("default source returns no entities")
    func defaultSourceReturnsEmpty() async throws {
        let query = ReleaseEntityQuery()
        let anyID = ReleaseEntity(artistName: "Juana Molina", releaseTitle: "Halo").id

        let entities = try await query.entities(for: [anyID])

        #expect(entities.isEmpty)
    }

    @Test("suggestedEntities returns [] in this slice")
    func suggestedEntitiesEmpty() async throws {
        let query = ReleaseEntityQuery()

        let suggestions = try await query.suggestedEntities()

        #expect(suggestions.isEmpty)
    }
}
