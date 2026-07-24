//
//  ArtistEntityTests.swift
//  WXYCIntents
//
//  Verifies ArtistEntity's dedup contract: artist-name variations ("Stereolab"
//  vs "Stereolab feat. …", casing, extra whitespace) normalize to the same
//  entity id and displayable name, and that the id is derived deterministically
//  (not via `String.hashValue`, which is randomized per process launch).
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

    @Test("displayRepresentation title uses the normalized name")
    func displayRepresentationUsesNormalizedName() {
        let entity = ArtistEntity(artistName: "Stereolab feat. Nurse With Wound")

        let title = String(localized: entity.displayRepresentation.title)

        #expect(title == "stereolab")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("attribute set ties back to the entity id for Spotlight resolution")
    func attributeSetCarriesRelatedIdentifier() {
        let entity = ArtistEntity(artistName: "Chuquimamani-Condori")

        let set = entity.attributeSet

        #expect(set.title == entity.normalizedName)
        #expect(set.relatedUniqueIdentifier == entity.id.entityIdentifierString)
    }
    #endif
}
