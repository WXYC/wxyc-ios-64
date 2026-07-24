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
import Concerts
import ConcertsTesting
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

    // MARK: - #646: representative display casing

    @Test("entities(for:) displays a representative original-cased name per deduped group, matching the donation path's rule")
    func entitiesForIdentifiersDisplaysRepresentativeCasing() async throws {
        // Regression for #646: entities(for:) used to hand ArtistEntity the
        // lowercased normalized key as its artistName, so a group like this
        // (a clean casing plus a lowercased "feat." variant) rendered
        // "stereolab" in Spotlight/Siri instead of the clean original casing
        // the donation path (#640/#644) already shows.
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab")
        let stereolabFeaturing = Playcut.stub(id: 2, artistName: "stereolab feat. Nurse With Wound")
        let query = ArtistEntityQuery(source: { [stereolab, stereolabFeaturing] })
        let wantedID = ArtistEntity(artistName: "Stereolab").id

        let entities = try await query.entities(for: [wantedID])

        let entity = try #require(entities.first)
        #expect(entity.id == wantedID)
        #expect(entity.displayName == "Stereolab")
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

    // MARK: - OT-C6: concerts(forArtist:)

    @Test("concerts(forArtist:) returns curated concerts headlined by the artist's catalog id")
    func concertsForArtistReturnsMatchingCuratedConcerts() async throws {
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab", artistId: 512)
        let concert = Concert.stub(id: 4821, headliningArtistRaw: "Stereolab", headliningArtistId: 512)
        let query = ArtistEntityQuery(source: { [stereolab] }, concertSource: { [concert] })
        let stereolabID = ArtistEntity(artistName: "Stereolab").id

        let matches = try await query.concerts(forArtist: stereolabID)

        #expect(matches == [concert])
    }

    @Test("concerts(forArtist:) returns an empty array when no concert headlines the artist's catalog id")
    func concertsForArtistReturnsEmptyForUnmatchedCatalogId() async throws {
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab", artistId: 512)
        let unrelatedConcert = Concert.stub(id: 1, headliningArtistRaw: "Cat Power", headliningArtistId: 999)
        let query = ArtistEntityQuery(source: { [stereolab] }, concertSource: { [unrelatedConcert] })
        let stereolabID = ArtistEntity(artistName: "Stereolab").id

        let matches = try await query.concerts(forArtist: stereolabID)

        #expect(matches.isEmpty)
    }

    @Test("concerts(forArtist:) never falls back to name matching when the artist has no resolved catalog id")
    func concertsForArtistNeverFallsBackToNameMatching() async throws {
        // Regression for the OT-C6 "no name matching" invariant: the concert's
        // headliningArtistRaw matches the playcut's artistName exactly, but the
        // playcut never resolved a catalog artistId, so there is nothing to
        // intersect on and the match must not happen anyway.
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab")
        let sameNameConcert = Concert.stub(id: 1, headliningArtistRaw: "Stereolab", headliningArtistId: 512)
        let query = ArtistEntityQuery(source: { [stereolab] }, concertSource: { [sameNameConcert] })
        let stereolabID = ArtistEntity(artistName: "Stereolab").id

        let matches = try await query.concerts(forArtist: stereolabID)

        #expect(matches.isEmpty)
    }

    @Test("concerts(forArtist:) filters out concerts with no resolved headliningArtistId, matching ForYouShelf's curated discipline")
    func concertsForArtistIgnoresUncuratedConcerts() async throws {
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab", artistId: 512)
        let uncuratedConcert = Concert.stub(id: 1, headliningArtistRaw: "Stereolab", headliningArtistId: nil)
        let query = ArtistEntityQuery(source: { [stereolab] }, concertSource: { [uncuratedConcert] })
        let stereolabID = ArtistEntity(artistName: "Stereolab").id

        let matches = try await query.concerts(forArtist: stereolabID)

        #expect(matches.isEmpty)
    }

    @Test("concerts(forArtist:) default concert source returns an empty array")
    func concertsForArtistDefaultSourceReturnsEmpty() async throws {
        let stereolab = Playcut.stub(id: 1, artistName: "Stereolab", artistId: 512)
        let query = ArtistEntityQuery(source: { [stereolab] })
        let stereolabID = ArtistEntity(artistName: "Stereolab").id

        let matches = try await query.concerts(forArtist: stereolabID)

        #expect(matches.isEmpty)
    }
}
