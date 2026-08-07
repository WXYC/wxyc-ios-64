//
//  EntityQueryConformanceTests.swift
//  WXYCIntents
//
//  Parameterized replacement for DJEntityQueryTests, LabelEntityQueryTests,
//  ReleaseEntityQueryTests, ShowEntityQueryTests, and VenueEntityQueryTests
//  (#760): those five files repeated the same `entities(for:)` contract test
//  across the two mechanical axes `EntityQueryResolution.swift` factors out
//  in production code — "derived-by-normalization" (DJ/Label/Release: no
//  id-scoped fetch, the full source is deduped) and "keyed-by-backend-id"
//  (Show/Venue: `identifiers` bridges into the source's own id space first).
//
//  `ArtistEntityQueryTests`, `ConcertEntityQueryTests`, and
//  `PlaycutEntityQueryTests` are NOT folded in here — each carries behavior
//  beyond this shared shape (Artist's play-count/representative-casing/
//  concerts-for-artist queries; Concert/Playcut's `@Dependency`-backed
//  production wiring and, for Playcut, real-`PlaycutHistoryStore`
//  resolution) — so they keep their own dedicated files.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Concerts
import ConcertsTesting
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("Derived-by-normalization query conformance")
struct DerivedQueryConformanceTests {
    @Test("dedups source items with name variations to a single resolvable entity", arguments: derivedQueryConformanceCases)
    func dedupsVariantsToSingleEntity(_ testCase: DerivedQueryConformanceCase) async throws {
        try await testCase.dedupsVariantsToSingleEntity()
    }

    @Test("skips source items with nothing to key on", arguments: derivedQueryConformanceCases)
    func skipsSourceItemsWithNoKey(_ testCase: DerivedQueryConformanceCase) async throws {
        try await testCase.skipsSourceItemsWithNoKey()
    }

    @Test("returns only the entities the source can resolve", arguments: derivedQueryConformanceCases)
    func dropsUnknownIdentifiers(_ testCase: DerivedQueryConformanceCase) async throws {
        try await testCase.dropsUnknownIdentifiers()
    }

    @Test("default source returns no entities", arguments: derivedQueryConformanceCases)
    func defaultSourceReturnsEmpty(_ testCase: DerivedQueryConformanceCase) async throws {
        try await testCase.defaultSourceYieldsNoEntities()
    }

    @Test("suggestedEntities returns []", arguments: derivedQueryConformanceCases)
    func suggestedEntitiesEmpty(_ testCase: DerivedQueryConformanceCase) async throws {
        try await testCase.suggestedEntitiesIsEmpty()
    }
}

@Suite("Keyed-by-backend-id query conformance")
struct KeyedQueryConformanceTests {
    @Test("resolves identifiers via the injected source", arguments: keyedQueryConformanceCases)
    func resolvesViaInjectedSource(_ testCase: KeyedQueryConformanceCase) async throws {
        try await testCase.resolvesInSourceOrder()
    }

    @Test("preserves the caller's identifier order even when the source returns them re-ordered", arguments: keyedQueryConformanceCases)
    func preservesCallerOrder(_ testCase: KeyedQueryConformanceCase) async throws {
        try await testCase.resolvesWhenSourceReordersItems()
    }

    @Test("returns only the entities the source supplies", arguments: keyedQueryConformanceCases)
    func dropsUnknownIdentifiers(_ testCase: KeyedQueryConformanceCase) async throws {
        try await testCase.dropsUnknownIdentifiers()
    }

    @Test("default source returns no entities", arguments: keyedQueryConformanceCases)
    func defaultSourceReturnsEmpty(_ testCase: KeyedQueryConformanceCase) async throws {
        try await testCase.defaultSourceYieldsNoEntities()
    }

    @Test("suggestedEntities returns []", arguments: keyedQueryConformanceCases)
    func suggestedEntitiesEmpty(_ testCase: KeyedQueryConformanceCase) async throws {
        try await testCase.suggestedEntitiesIsEmpty()
    }
}

// MARK: - Mocks and descriptors

/// One "derived-by-normalization" `EntityQuery` under test — `DJEntityQuery`,
/// `LabelEntityQuery`, `ReleaseEntityQuery` today. Each closure is
/// self-contained (builds its own fixtures, runs the query, and asserts the
/// expected contract) so the shared `@Test` bodies above don't need to know
/// the concrete `EntityQuery`/`Entity`/source-model type. The `#expect`s live
/// inside these closures rather than being folded into a `Bool` the `@Test`
/// asserts on: a returned `Bool` reports only `-> false` on failure, with no
/// actual/expected values and no indication of which half of a compound
/// condition broke -- strictly worse triage than the per-type files this
/// replaced. Which case failed is still legible, since the parameterized
/// test's name carries the argument.
struct DerivedQueryConformanceCase: Sendable {
    let typeName: String
    let dedupsVariantsToSingleEntity: @Sendable () async throws -> Void
    let skipsSourceItemsWithNoKey: @Sendable () async throws -> Void
    let dropsUnknownIdentifiers: @Sendable () async throws -> Void
    let defaultSourceYieldsNoEntities: @Sendable () async throws -> Void
    let suggestedEntitiesIsEmpty: @Sendable () async throws -> Void
}

let derivedQueryConformanceCases: [DerivedQueryConformanceCase] = [
    DerivedQueryConformanceCase(
        typeName: "DJEntityQuery",
        dedupsVariantsToSingleEntity: {
            let jake = ShowMarker.stub(id: 1, djName: "Jake B")
            let jakeMessy = ShowMarker.stub(id: 2, djName: "  jake   b  ")
            let query = DJEntityQuery(source: { [jake, jakeMessy] })
            let entities = try await query.entities(for: [DJEntity(djName: "Jake B").id])
            #expect(entities.count == 1)
            #expect(entities.first?.normalizedName == "jake b")
        },
        skipsSourceItemsWithNoKey: {
            let unnamed = ShowMarker.stub(id: 1, djName: nil)
            let jake = ShowMarker.stub(id: 2, djName: "Jake B")
            let query = DJEntityQuery(source: { [unnamed, jake] })
            let entities = try await query.entities(for: [DJEntity(djName: "Jake B").id])
            #expect(entities.count == 1)
            #expect(entities.first?.normalizedName == "jake b")
        },
        dropsUnknownIdentifiers: {
            let jake = ShowMarker.stub(id: 1, djName: "Jake B")
            let query = DJEntityQuery(source: { [jake] })
            let entities = try await query.entities(for: [DJEntity(djName: "DJ Rembert").id])
            #expect(entities.isEmpty)
        },
        defaultSourceYieldsNoEntities: {
            let query = DJEntityQuery()
            let entities = try await query.entities(for: [DJEntity(djName: "Jake B").id])
            #expect(entities.isEmpty)
        },
        suggestedEntitiesIsEmpty: {
            let suggestions = try await DJEntityQuery().suggestedEntities()
            #expect(suggestions.isEmpty)
        }
    ),
    DerivedQueryConformanceCase(
        typeName: "LabelEntityQuery",
        dedupsVariantsToSingleEntity: {
            let sonamos = Playcut.stub(id: 1, labelName: "Sonamos", artistName: "Juana Molina")
            let sonamosMessy = Playcut.stub(id: 2, labelName: "  sonamos  ", artistName: "Stereolab")
            let query = LabelEntityQuery(source: { [sonamos, sonamosMessy] })
            let entities = try await query.entities(for: [LabelEntity(labelName: "Sonamos").id])
            #expect(entities.count == 1)
            #expect(entities.first?.normalizedName == "sonamos")
        },
        skipsSourceItemsWithNoKey: {
            let noLabel = Playcut.stub(id: 1, labelName: nil, artistName: "Cat Power")
            let dragCity = Playcut.stub(id: 2, labelName: "Drag City", artistName: "Jessica Pratt")
            let query = LabelEntityQuery(source: { [noLabel, dragCity] })
            let entities = try await query.entities(for: [LabelEntity(labelName: "Drag City").id])
            #expect(entities.count == 1)
            #expect(entities.first?.normalizedName == "drag city")
        },
        dropsUnknownIdentifiers: {
            let dragCity = Playcut.stub(id: 1, labelName: "Drag City", artistName: "Jessica Pratt")
            let query = LabelEntityQuery(source: { [dragCity] })
            let entities = try await query.entities(for: [LabelEntity(labelName: "Merge Records").id])
            #expect(entities.isEmpty)
        },
        defaultSourceYieldsNoEntities: {
            let query = LabelEntityQuery()
            let entities = try await query.entities(for: [LabelEntity(labelName: "Drag City").id])
            #expect(entities.isEmpty)
        },
        suggestedEntitiesIsEmpty: {
            let suggestions = try await LabelEntityQuery().suggestedEntities()
            #expect(suggestions.isEmpty)
        }
    ),
    DerivedQueryConformanceCase(
        typeName: "ReleaseEntityQuery",
        dedupsVariantsToSingleEntity: {
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
        },
        skipsSourceItemsWithNoKey: {
            let noRelease = Playcut.stub(id: 1, artistName: "Cat Power", releaseTitle: nil)
            let withRelease = Playcut.stub(id: 2, artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again")
            let query = ReleaseEntityQuery(source: { [noRelease, withRelease] })
            let wantedID = ReleaseEntity(artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again").id
            let entities = try await query.entities(for: [wantedID])
            #expect(entities.count == 1)
            #expect(entities.first?.normalizedReleaseTitle == "on your own love again")
        },
        dropsUnknownIdentifiers: {
            let halo = Playcut.stub(id: 1, artistName: "Juana Molina", releaseTitle: "Halo")
            let query = ReleaseEntityQuery(source: { [halo] })
            let unknownID = ReleaseEntity(artistName: "Cat Power", releaseTitle: "Moon Pix").id
            let entities = try await query.entities(for: [unknownID])
            #expect(entities.isEmpty)
        },
        defaultSourceYieldsNoEntities: {
            let query = ReleaseEntityQuery()
            let anyID = ReleaseEntity(artistName: "Juana Molina", releaseTitle: "Halo").id
            let entities = try await query.entities(for: [anyID])
            #expect(entities.isEmpty)
        },
        suggestedEntitiesIsEmpty: {
            let suggestions = try await ReleaseEntityQuery().suggestedEntities()
            #expect(suggestions.isEmpty)
        }
    ),
]

/// One "keyed-by-backend-id" `EntityQuery` under test — `ShowEntityQuery`,
/// `VenueEntityQuery` today. `ConcertEntityQuery`/`PlaycutEntityQuery` also
/// use this axis in production (see `EntityQueryResolution.swift`) but keep
/// their own test files — see this file's header.
struct KeyedQueryConformanceCase: Sendable {
    let typeName: String
    let resolvesInSourceOrder: @Sendable () async throws -> Void
    let resolvesWhenSourceReordersItems: @Sendable () async throws -> Void
    let dropsUnknownIdentifiers: @Sendable () async throws -> Void
    let defaultSourceYieldsNoEntities: @Sendable () async throws -> Void
    let suggestedEntitiesIsEmpty: @Sendable () async throws -> Void
}

let keyedQueryConformanceCases: [KeyedQueryConformanceCase] = [
    KeyedQueryConformanceCase(
        typeName: "ShowEntityQuery",
        resolvesInSourceOrder: {
            let jake = ShowMarker.stub(id: 1, djName: "Jake B")
            let dee = ShowMarker.stub(id: 2, djName: "Dee Jay")
            let source: ShowEntityQuery.ShowSource = { ids in [jake, dee].filter { ids.contains($0.id) } }
            let query = ShowEntityQuery(source: source)
            let entities = try await query.entities(for: [ShowID(1), ShowID(2)])
            #expect(entities.map(\.id) == [ShowID(1), ShowID(2)])
        },
        resolvesWhenSourceReordersItems: {
            let jake = ShowMarker.stub(id: 1, djName: "Jake B")
            let dee = ShowMarker.stub(id: 2, djName: "Dee Jay")
            let source: ShowEntityQuery.ShowSource = { _ in [dee, jake] }
            let query = ShowEntityQuery(source: source)
            let entities = try await query.entities(for: [ShowID(1), ShowID(2)])
            #expect(entities.map(\.id) == [ShowID(1), ShowID(2)])
        },
        dropsUnknownIdentifiers: {
            let jake = ShowMarker.stub(id: 1, djName: "Jake B")
            let source: ShowEntityQuery.ShowSource = { ids in [jake].filter { ids.contains($0.id) } }
            let query = ShowEntityQuery(source: source)
            let entities = try await query.entities(for: [ShowID(1), ShowID(999)])
            #expect(entities.map(\.id) == [ShowID(1)])
        },
        defaultSourceYieldsNoEntities: {
            let query = ShowEntityQuery()
            let entities = try await query.entities(for: [ShowID(1), ShowID(2), ShowID(3)])
            #expect(entities.isEmpty)
        },
        suggestedEntitiesIsEmpty: {
            let suggestions = try await ShowEntityQuery().suggestedEntities()
            #expect(suggestions.isEmpty)
        }
    ),
    KeyedQueryConformanceCase(
        typeName: "VenueEntityQuery",
        resolvesInSourceOrder: {
            let catsCradle = Venue.stub(id: 1, name: "Cat's Cradle")
            let motorco = Venue.stub(id: 2, name: "Motorco Music Hall")
            let source: VenueEntityQuery.VenueSource = { ids in [catsCradle, motorco].filter { ids.contains($0.id) } }
            let query = VenueEntityQuery(source: source)
            let catsCradleID = try #require(VenueID(venueID: 1))
            let motorcoID = try #require(VenueID(venueID: 2))
            let entities = try await query.entities(for: [catsCradleID, motorcoID])
            #expect(entities.map(\.id) == [catsCradleID, motorcoID])
        },
        resolvesWhenSourceReordersItems: {
            let catsCradle = Venue.stub(id: 1, name: "Cat's Cradle")
            let motorco = Venue.stub(id: 2, name: "Motorco Music Hall")
            let source: VenueEntityQuery.VenueSource = { _ in [motorco, catsCradle] }
            let query = VenueEntityQuery(source: source)
            let catsCradleID = try #require(VenueID(venueID: 1))
            let motorcoID = try #require(VenueID(venueID: 2))
            let entities = try await query.entities(for: [catsCradleID, motorcoID])
            #expect(entities.map(\.id) == [catsCradleID, motorcoID])
        },
        dropsUnknownIdentifiers: {
            let catsCradle = Venue.stub(id: 1, name: "Cat's Cradle")
            let source: VenueEntityQuery.VenueSource = { ids in [catsCradle].filter { ids.contains($0.id) } }
            let query = VenueEntityQuery(source: source)
            let catsCradleID = try #require(VenueID(venueID: 1))
            let unknownID = try #require(VenueID(venueID: 999))
            let entities = try await query.entities(for: [catsCradleID, unknownID])
            #expect(entities.map(\.id) == [catsCradleID])
        },
        defaultSourceYieldsNoEntities: {
            let query = VenueEntityQuery()
            let ids = try [1, 2, 3].map { try #require(VenueID(venueID: $0)) }
            let entities = try await query.entities(for: ids)
            #expect(entities.isEmpty)
        },
        suggestedEntitiesIsEmpty: {
            let suggestions = try await VenueEntityQuery().suggestedEntities()
            #expect(suggestions.isEmpty)
        }
    ),
]
