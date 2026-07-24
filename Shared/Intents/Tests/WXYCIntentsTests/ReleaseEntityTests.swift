//
//  ReleaseEntityTests.swift
//  WXYCIntents
//
//  Verifies ReleaseEntity's dedup contract: the id is a composite of the
//  normalized artist name and normalized release title, so name variations
//  ("feat. …", casing, whitespace) on either half dedup to the same entity,
//  while distinct releases (even by the same artist) produce distinct ids.
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

@Suite("ReleaseEntity")
struct ReleaseEntityTests {
    @Test("same artist and release with a 'feat.' variation dedup to a single entity")
    func featureClauseVariationsDedupToOneEntity() {
        let stereolab = Playcut.stub(artistName: "Stereolab", releaseTitle: "Dots and Loops")
        let stereolabFeaturing = Playcut.stub(
            artistName: "Stereolab feat. Nurse With Wound",
            releaseTitle: "Dots and Loops"
        )

        let entity = ReleaseEntity(artistName: stereolab.artistName, releaseTitle: stereolab.releaseTitle ?? "")
        let featuringEntity = ReleaseEntity(
            artistName: stereolabFeaturing.artistName,
            releaseTitle: stereolabFeaturing.releaseTitle ?? ""
        )

        #expect(entity.id == featuringEntity.id)
    }

    @Test("differing case and surrounding whitespace on both halves normalize to the same key")
    func caseAndWhitespaceVariationsDedupToOneEntity() {
        let entity = ReleaseEntity(artistName: "Cat Power", releaseTitle: "Moon Pix")
        let messyEntity = ReleaseEntity(artistName: "  cat   power  ", releaseTitle: "  moon   pix  ")

        #expect(entity.id == messyEntity.id)
        #expect(messyEntity.normalizedReleaseTitle == "moon pix")
        #expect(messyEntity.normalizedArtistName == "cat power")
    }

    @Test("id is identical across two independent constructions from the same names")
    func idIsStableAcrossConstructions() {
        let first = ReleaseEntity(artistName: "Juana Molina", releaseTitle: "Halo")
        let second = ReleaseEntity(artistName: "Juana Molina", releaseTitle: "Halo")

        #expect(first.id == second.id)
        #expect(first.id.value == second.id.value)
    }

    @Test("same artist, different release titles produce distinct ids")
    func distinctReleaseTitlesProduceDistinctIDs() {
        let halo = ReleaseEntity(artistName: "Juana Molina", releaseTitle: "Halo")
        let doga = ReleaseEntity(artistName: "Juana Molina", releaseTitle: "DOGA")

        #expect(halo.id != doga.id)
    }

    @Test("same release title, different artists produce distinct ids")
    func distinctArtistsProduceDistinctIDs() {
        let juana = ReleaseEntity(artistName: "Juana Molina", releaseTitle: "Halo")
        let stereolab = ReleaseEntity(artistName: "Stereolab", releaseTitle: "Halo")

        #expect(juana.id != stereolab.id)
    }

    @Test("displayRepresentation title is the release, subtitle is the artist")
    func displayRepresentationUsesReleaseAndArtist() {
        let entity = ReleaseEntity(artistName: "Stereolab feat. Nurse With Wound", releaseTitle: "Dots and Loops")

        let title = String(localized: entity.displayRepresentation.title)
        let subtitle = entity.displayRepresentation.subtitle.map { String(localized: $0) }

        #expect(title == "dots and loops")
        #expect(subtitle == "stereolab")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("attribute set ties back to the entity id for Spotlight resolution")
    func attributeSetCarriesRelatedIdentifier() {
        let entity = ReleaseEntity(artistName: "Chuquimamani-Condori", releaseTitle: "Edits")

        let set = entity.attributeSet

        #expect(set.title == entity.normalizedReleaseTitle)
        #expect(set.relatedUniqueIdentifier == entity.id.entityIdentifierString)
    }
    #endif
}
