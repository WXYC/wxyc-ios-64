//
//  LabelEntityTests.swift
//  WXYCIntents
//
//  Verifies LabelEntity's dedup contract: label-name casing/whitespace
//  variations normalize to the same entity id and displayable name, and that
//  the id is derived deterministically (not via `String.hashValue`, which is
//  randomized per process launch).
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import WXYCIntents
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

@Suite("LabelEntity")
struct LabelEntityTests {
    @Test("differing case and surrounding whitespace normalize to the same key")
    func caseAndWhitespaceVariationsDedupToOneEntity() {
        let entity = LabelEntity(labelName: "Merge Records")
        let messyEntity = LabelEntity(labelName: "  merge   records  ")

        #expect(entity.id == messyEntity.id)
        #expect(entity.normalizedName == "merge records")
    }

    @Test("id is identical across two independent constructions from the same name")
    func idIsStableAcrossConstructions() {
        let first = LabelEntity(labelName: "Trekky Records")
        let second = LabelEntity(labelName: "Trekky Records")

        #expect(first.id == second.id)
        #expect(first.id.value == second.id.value)
    }

    @Test("distinct labels produce distinct ids")
    func distinctLabelsProduceDistinctIDs() {
        let trekky = LabelEntity(labelName: "Trekky Records")
        let merge = LabelEntity(labelName: "Merge Records")

        #expect(trekky.id != merge.id)
    }

    @Test("displayRepresentation title uses the normalized name")
    func displayRepresentationUsesNormalizedName() {
        let entity = LabelEntity(labelName: "  Merge Records  ")

        let title = String(localized: entity.displayRepresentation.title)

        #expect(title == "merge records")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("attribute set ties back to the entity id for Spotlight resolution")
    func attributeSetCarriesRelatedIdentifier() {
        let entity = LabelEntity(labelName: "Sonamos")

        let set = entity.attributeSet

        #expect(set.title == entity.normalizedName)
        #expect(set.relatedUniqueIdentifier == entity.id.entityIdentifierString)
    }
    #endif
}
