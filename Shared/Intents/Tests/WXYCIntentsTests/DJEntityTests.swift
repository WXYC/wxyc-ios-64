//
//  DJEntityTests.swift
//  WXYCIntents
//
//  Verifies DJEntity's dedup contract: djName case/whitespace variations
//  normalize to the same entity id and displayable name, and that the id is
//  derived deterministically (not via `String.hashValue`, which is
//  randomized per process launch), mirroring ArtistEntityTests.
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

@Suite("DJEntity")
struct DJEntityTests {
    @Test("differing case and surrounding whitespace normalize to the same key")
    func caseAndWhitespaceVariationsDedupToOneEntity() {
        let entity = DJEntity(djName: "Jake B")
        let messyEntity = DJEntity(djName: "  jake   b  ")

        #expect(entity.id == messyEntity.id)
        #expect(entity.normalizedName == "jake b")
    }

    @Test("id is identical across two independent constructions from the same name")
    func idIsStableAcrossConstructions() {
        let first = DJEntity(djName: "Jake B")
        let second = DJEntity(djName: "Jake B")

        #expect(first.id == second.id)
        #expect(first.id.value == second.id.value)
    }

    @Test("distinct DJs produce distinct ids")
    func distinctDJsProduceDistinctIDs() {
        let jake = DJEntity(djName: "Jake B")
        let other = DJEntity(djName: "DJ Rembert")

        #expect(jake.id != other.id)
    }

    @Test("displayRepresentation title uses the normalized name")
    func displayRepresentationUsesNormalizedName() {
        let entity = DJEntity(djName: "  Jake   B  ")

        let title = String(localized: entity.displayRepresentation.title)

        #expect(title == "jake b")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("attribute set ties back to the entity id for Spotlight resolution")
    func attributeSetCarriesRelatedIdentifier() {
        let entity = DJEntity(djName: "Jake B")

        let set = entity.attributeSet

        #expect(set.title == entity.normalizedName)
        #expect(set.relatedUniqueIdentifier == entity.id.entityIdentifierString)
    }
    #endif
}
