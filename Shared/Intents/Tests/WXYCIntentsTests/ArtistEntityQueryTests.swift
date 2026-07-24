//
//  ArtistEntityQueryTests.swift
//  WXYCIntents
//
//  Verifies ArtistEntityQuery's identifier-lookup path: the injected playcut
//  source is deduped by normalized artist name before resolving the caller's
//  requested ids, and the safe empty defaults used by the F5b slice. C6 adds
//  the richer per-artist query — "all playcuts where normalized artistName ==
//  self.key" — plus the play-count computation the same dedup grouping
//  produces for free.
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

    // MARK: - C6: play count

    @Test("entities(for:) carries the play count of all name-variant matches")
    func entitiesForIdentifiersIncludesPlayCount() async throws {
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab")
        let stereolabFeaturing = Playcut.stub(id: 2, artistName: "Stereolab feat. Nurse With Wound")
        let stereolabMessy = Playcut.stub(id: 3, artistName: "  STEREOLAB  ")
        let query = ArtistEntityQuery(source: { [stereolab, stereolabFeaturing, stereolabMessy] })
        let wantedID = ArtistEntity(artistName: "Stereolab").id

        let entities = try await query.entities(for: [wantedID])

        #expect(entities.first?.playCount == 3)
    }

    @Test("entities(for:) computes play count independently per artist")
    func entitiesForIdentifiersComputesPlayCountPerArtist() async throws {
        let juanaFirst = Playcut.stub(id: 1, artistName: "Juana Molina")
        let juanaSecond = Playcut.stub(id: 2, artistName: "Juana Molina")
        let catPower = Playcut.stub(id: 3, artistName: "Cat Power")
        let query = ArtistEntityQuery(source: { [juanaFirst, juanaSecond, catPower] })
        let juanaID = ArtistEntity(artistName: "Juana Molina").id
        let catPowerID = ArtistEntity(artistName: "Cat Power").id

        let entities = try await query.entities(for: [juanaID, catPowerID])

        let juanaEntity = try #require(entities.first { $0.id == juanaID })
        let catPowerEntity = try #require(entities.first { $0.id == catPowerID })
        #expect(juanaEntity.playCount == 2)
        #expect(catPowerEntity.playCount == 1)
    }

    // MARK: - C6: playcuts(forArtist:)

    @Test("playcuts(forArtist:) returns every playcut matching the normalized artist name, including variants")
    func playcutsForArtistReturnsAllNameVariants() async throws {
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab")
        let stereolabFeaturing = Playcut.stub(id: 2, artistName: "Stereolab feat. Nurse With Wound")
        let stereolabMessy = Playcut.stub(id: 3, artistName: "  STEREOLAB  ")
        let catPower = Playcut.stub(id: 4, artistName: "Cat Power")
        let query = ArtistEntityQuery(source: { [stereolab, stereolabFeaturing, stereolabMessy, catPower] })
        let stereolabID = ArtistEntity(artistName: "Stereolab").id

        let matches = try await query.playcuts(forArtist: stereolabID)

        #expect(Set(matches.map(\.id)) == [1, 2, 3])
    }

    @Test("playcuts(forArtist:) returns an empty array for an artist the source never played")
    func playcutsForArtistReturnsEmptyForUnknownArtist() async throws {
        let juana = Playcut.stub(id: 1, artistName: "Juana Molina")
        let query = ArtistEntityQuery(source: { [juana] })
        let unknownID = ArtistEntity(artistName: "Cat Power").id

        let matches = try await query.playcuts(forArtist: unknownID)

        #expect(matches.isEmpty)
    }
}
