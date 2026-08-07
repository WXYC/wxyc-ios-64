//
//  NormalizedKeyEntityConformanceTests.swift
//  WXYCIntents
//
//  Parameterized replacement for DJEntityTests, LabelEntityTests,
//  ArtistEntityTests, and ReleaseEntityTests (#760): those four files
//  repeated the same dedup/id-stability/attribute-set contract with only
//  fixture strings (and, for DJ/Label, nothing else) varying. `DJEntity` and
//  `LabelEntity` share the exact `NormalizedNameEntity` shape, so they drive
//  the same `NormalizedKeyEntityCase` descriptor `ArtistEntity` does; Artist's
//  extra fields (`displayName`, `playCount`) get their own dedicated tests
//  below, and `ReleaseEntity`'s two-part composite key doesn't fit a
//  single-raw-string descriptor, so it keeps its own small parameterized
//  group instead of forcing an artificial shared shape.
//
//  Created by Jake Bromberg on 08/05/26.
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

@Suite("Normalized-key entity conformance")
struct NormalizedKeyEntityConformanceTests {
    @Test("dedup variants normalize to the same id and dedup key", arguments: normalizedKeyEntityCases)
    func dedupVariantsShareIdentity(_ testCase: NormalizedKeyEntityCase) {
        let canonicalID = testCase.entityIdentifierString(testCase.rawValue)
        #expect(testCase.normalizedName(testCase.rawValue) == testCase.expectedNormalizedName)

        for variant in testCase.dedupVariants {
            #expect(testCase.entityIdentifierString(variant) == canonicalID)
            #expect(testCase.normalizedName(variant) == testCase.expectedNormalizedName)
        }
    }

    @Test("id is stable across independent constructions from the same raw value", arguments: normalizedKeyEntityCases)
    func idIsStableAcrossConstructions(_ testCase: NormalizedKeyEntityCase) {
        #expect(testCase.entityIdentifierString(testCase.rawValue) == testCase.entityIdentifierString(testCase.rawValue))
    }

    @Test("distinct raw values produce distinct ids", arguments: normalizedKeyEntityCases)
    func distinctRawValuesProduceDistinctIDs(_ testCase: NormalizedKeyEntityCase) {
        #expect(testCase.entityIdentifierString(testCase.rawValue) != testCase.entityIdentifierString(testCase.distinctRawValue))
    }

    @Test("displayRepresentation renders the expected title", arguments: normalizedKeyEntityCases)
    func displayRepresentationRendersExpectedTitle(_ testCase: NormalizedKeyEntityCase) {
        #expect(testCase.displayTitle(testCase.rawValue) == testCase.expectedTitle)
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("attribute set carries the expected title and ties back to the entity id", arguments: normalizedKeyEntityCases)
    func attributeSetCarriesExpectedFields(_ testCase: NormalizedKeyEntityCase) {
        let fields = testCase.attributeSetFields(testCase.rawValue)

        #expect(fields.title == testCase.expectedTitle)
        #expect(fields.relatedUniqueIdentifier == testCase.entityIdentifierString(testCase.rawValue))
    }
    #endif
}

// MARK: - ArtistEntity: fields NormalizedKeyEntityCase doesn't generalize

@Suite("ArtistEntity extras")
struct ArtistEntityExtraTests {
    @Test("displayName preserves original casing while normalizedName stays lowercased")
    func displayNamePreservesOriginalCasing() {
        let entity = ArtistEntity(artistName: "Stereolab")

        #expect(entity.displayName == "Stereolab")
        #expect(entity.normalizedName == "stereolab")
    }

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

    #if !os(watchOS) && !os(tvOS)
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
}

// MARK: - ReleaseEntity: a two-part composite key doesn't fit the single-string descriptor

struct ReleaseDedupCase: Sendable {
    let artistName: String
    let releaseTitle: String
    let variantArtistName: String
    let variantReleaseTitle: String
}

let releaseDedupCases: [ReleaseDedupCase] = [
    ReleaseDedupCase(
        artistName: "Stereolab",
        releaseTitle: "Dots and Loops",
        variantArtistName: "Stereolab feat. Nurse With Wound",
        variantReleaseTitle: "Dots and Loops"
    ),
    ReleaseDedupCase(
        artistName: "Cat Power",
        releaseTitle: "Moon Pix",
        variantArtistName: "  cat   power  ",
        variantReleaseTitle: "  moon   pix  "
    ),
]

@Suite("ReleaseEntity")
struct ReleaseEntityConformanceTests {
    @Test("dedup variants on either half of the composite key share an id", arguments: releaseDedupCases)
    func dedupVariantsShareIdentity(_ testCase: ReleaseDedupCase) {
        let canonical = ReleaseEntity(artistName: testCase.artistName, releaseTitle: testCase.releaseTitle)
        let variant = ReleaseEntity(artistName: testCase.variantArtistName, releaseTitle: testCase.variantReleaseTitle)

        #expect(canonical.id == variant.id)
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

// MARK: - Mocks and descriptors

/// One F5x single-raw-string normalized-key `AppEntity` type under test —
/// `DJEntity`, `LabelEntity`, `ArtistEntity` today. Each case supplies just
/// enough closures to drive the shared dedup/id-stability/attribute-set
/// assertions above without those assertions needing to know the concrete
/// `AppEntity`/`ID` type. Comparisons go through `entityIdentifierString`
/// (a `String`) rather than the concrete `EntityID<Owner>`, so cases whose
/// owner types differ can share one array.
struct NormalizedKeyEntityCase: Sendable {
    let typeName: String
    /// The canonical raw input (e.g. "Jake B").
    let rawValue: String
    /// Alternate raw inputs expected to normalize to the same dedup key as
    /// `rawValue` — casing/whitespace variants for every case, plus a
    /// trailing "feat. …" clause variant where the entity's normalization
    /// strips one (see `normalizedEntityKey` in ArtistIdentity.swift).
    let dedupVariants: [String]
    /// A raw input expected to produce a genuinely distinct entity.
    let distinctRawValue: String
    /// `normalizedName(rawValue)`'s expected value.
    let expectedNormalizedName: String
    /// `displayTitle(rawValue)`'s expected value — DJ/Label's own
    /// (lowercased) `normalizedName`, Artist's original-cased `displayName`.
    let expectedTitle: String
    let normalizedName: @Sendable (String) -> String
    let entityIdentifierString: @Sendable (String) -> String
    let displayTitle: @Sendable (String) -> String
    /// Reads the entity's Spotlight attribute set. Declared unconditionally
    /// even though only the `#if !os(watchOS) && !os(tvOS)` test above calls
    /// it: Swift has no `#if` inside an argument list, so gating the property
    /// would leave every `attributeSetFields:` argument in the case array
    /// below unconditional and break the watch/tv build outright. The
    /// condition lives inside each closure body instead, where the
    /// CoreSpotlight-only `attributeSet` is actually named; the `(nil, nil)`
    /// branch is unreachable, because its only caller is compiled out on the
    /// same platforms.
    let attributeSetFields: @Sendable (String) -> (title: String?, relatedUniqueIdentifier: String?)
}

let normalizedKeyEntityCases: [NormalizedKeyEntityCase] = [
    NormalizedKeyEntityCase(
        typeName: "DJEntity",
        rawValue: "Jake B",
        dedupVariants: ["  jake   b  "],
        distinctRawValue: "DJ Rembert",
        expectedNormalizedName: "jake b",
        expectedTitle: "jake b",
        normalizedName: { DJEntity(djName: $0).normalizedName },
        entityIdentifierString: { DJEntity(djName: $0).id.entityIdentifierString },
        displayTitle: { String(localized: DJEntity(djName: $0).displayRepresentation.title) },
        attributeSetFields: { raw in
            #if !os(watchOS) && !os(tvOS)
            let set = DJEntity(djName: raw).attributeSet
            return (set.title, set.relatedUniqueIdentifier)
            #else
            return (nil, nil)
            #endif
        }
    ),
    NormalizedKeyEntityCase(
        typeName: "LabelEntity",
        rawValue: "Trekky Records",
        dedupVariants: ["  trekky   records  "],
        distinctRawValue: "Merge Records",
        expectedNormalizedName: "trekky records",
        expectedTitle: "trekky records",
        normalizedName: { LabelEntity(labelName: $0).normalizedName },
        entityIdentifierString: { LabelEntity(labelName: $0).id.entityIdentifierString },
        displayTitle: { String(localized: LabelEntity(labelName: $0).displayRepresentation.title) },
        attributeSetFields: { raw in
            #if !os(watchOS) && !os(tvOS)
            let set = LabelEntity(labelName: raw).attributeSet
            return (set.title, set.relatedUniqueIdentifier)
            #else
            return (nil, nil)
            #endif
        }
    ),
    NormalizedKeyEntityCase(
        typeName: "ArtistEntity",
        rawValue: "Stereolab",
        dedupVariants: ["  stereolab  ", "STEREOLAB", "Stereolab feat. Nurse With Wound"],
        distinctRawValue: "Juana Molina",
        expectedNormalizedName: "stereolab",
        expectedTitle: "Stereolab",
        normalizedName: { ArtistEntity(artistName: $0).normalizedName },
        entityIdentifierString: { ArtistEntity(artistName: $0).id.entityIdentifierString },
        displayTitle: { String(localized: ArtistEntity(artistName: $0).displayRepresentation.title) },
        attributeSetFields: { raw in
            #if !os(watchOS) && !os(tvOS)
            let set = ArtistEntity(artistName: raw).attributeSet
            return (set.title, set.relatedUniqueIdentifier)
            #else
            return (nil, nil)
            #endif
        }
    ),
]
