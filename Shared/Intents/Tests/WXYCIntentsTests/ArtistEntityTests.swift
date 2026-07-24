//
//  ArtistEntityTests.swift
//  WXYCIntents
//
//  Verifies ArtistEntity's dedup contract: artist-name variations ("Stereolab"
//  vs "Stereolab feat. …", casing, extra whitespace) normalize to the same
//  entity id, and that the id is derived deterministically (not via
//  `String.hashValue`, which is randomized per process launch). Also verifies
//  the display contract: `displayName` preserves the original casing/text
//  passed to `init`, distinct from the lowercased `normalizedName` dedup key
//  (issue #640 — entities used to display the normalized key itself).
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

@Suite("ArtistEntity")
struct ArtistEntityTests {
    @Test("playcuts with a 'feat.' variation dedup to a single entity")
    func featureClauseVariationsDedupToOneEntity() {
        let stereolab = Playcut.stub(artistName: "Stereolab")
        let stereolabFeaturing = Playcut.stub(artistName: "Stereolab feat. Nurse With Wound")

        let entity = ArtistEntity(artistName: stereolab.artistName)
        let featuringEntity = ArtistEntity(artistName: stereolabFeaturing.artistName)

        #expect(entity.id == featuringEntity.id)
        #expect(entity.normalizedName == featuringEntity.normalizedName)
    }

    @Test("differing case and surrounding whitespace normalize to the same key")
    func caseAndWhitespaceVariationsDedupToOneEntity() {
        let entity = ArtistEntity(artistName: "Cat Power")
        let messyEntity = ArtistEntity(artistName: "  cat   power  ")

        #expect(entity.id == messyEntity.id)
        #expect(entity.normalizedName == "cat power")
    }

    @Test("id is identical across two independent constructions from the same name")
    func idIsStableAcrossConstructions() {
        let first = ArtistEntity(artistName: "Juana Molina")
        let second = ArtistEntity(artistName: "Juana Molina")

        #expect(first.id == second.id)
        #expect(first.id.value == second.id.value)
    }

    @Test("distinct artists produce distinct ids")
    func distinctArtistsProduceDistinctIDs() {
        let juana = ArtistEntity(artistName: "Juana Molina")
        let stereolab = ArtistEntity(artistName: "Stereolab")

        #expect(juana.id != stereolab.id)
    }

    @Test("id stays stable across casing variants even though displayName differs per instance")
    func idStableAcrossCasingVariantsWithDifferingDisplayNames() {
        // Regression for #640: the entity used to display `normalizedName`
        // (the lowercased dedup key) directly, so "Stereolab" rendered as
        // "stereolab". `id` must stay keyed on the normalized form no matter
        // which casing variant built the entity, while `displayName` is free
        // to differ per instance.
        let properCase = ArtistEntity(artistName: "Stereolab")
        let allCaps = ArtistEntity(artistName: "STEREOLAB")

        #expect(properCase.id == allCaps.id)
        #expect(properCase.normalizedName == allCaps.normalizedName)
        #expect(properCase.displayName == "Stereolab")
        #expect(allCaps.displayName == "STEREOLAB")
    }

    @Test("displayName preserves original casing while normalizedName stays lowercased")
    func displayNamePreservesOriginalCasing() {
        let entity = ArtistEntity(artistName: "Stereolab")

        #expect(entity.displayName == "Stereolab")
        #expect(entity.normalizedName == "stereolab")
    }

    @Test("displayRepresentation title uses the display name, not the normalized key")
    func displayRepresentationUsesDisplayName() {
        let entity = ArtistEntity(artistName: "Stereolab")

        let title = String(localized: entity.displayRepresentation.title)

        #expect(title == "Stereolab")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("attribute set ties back to the entity id for Spotlight resolution")
    func attributeSetCarriesRelatedIdentifier() {
        let entity = ArtistEntity(artistName: "Chuquimamani-Condori")

        let set = entity.attributeSet

        #expect(set.title == entity.displayName)
        #expect(set.relatedUniqueIdentifier == entity.id.entityIdentifierString)
    }

    @Test("attribute set indexes the artist field for search")
    func attributeSetCarriesArtistField() {
        let entity = ArtistEntity(artistName: "Chuquimamani-Condori")

        let set = entity.attributeSet

        #expect(set.artist == entity.displayName)
    }

    @Test("attribute set carries the play count under its custom indexing key")
    func attributeSetCarriesPlayCount() throws {
        let entity = ArtistEntity(artistName: "Stereolab", playCount: 7)

        let set = entity.attributeSet
        let key = try #require(ArtistEntity.playCountKey)

        #expect(set.value(forCustomKey: key) as? Int == 7)
    }
    #endif

    @Test("playCount defaults to zero when not provided")
    func playCountDefaultsToZero() {
        let entity = ArtistEntity(artistName: "Jessica Pratt")

        #expect(entity.playCount == 0)
    }

    @Test("playCount is carried on the entity when provided")
    func playCountIsStored() {
        let entity = ArtistEntity(artistName: "Duke Ellington & John Coltrane", playCount: 12)

        #expect(entity.playCount == 12)
    }
}
