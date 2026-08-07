//
//  EntityQueryResolution.swift
//  Intents
//
//  Shared `entities(for:)` body for every WXYC EntityQuery — the query-side
//  counterpart to `NormalizedNameEntity` on the entity side. Every F5x/F1/
//  OT-F4 query repeated the same tail (build a `Dictionary` keyed by id,
//  first entry wins on a duplicate; look up the caller's requested ids in
//  the caller's order, dropping anything unresolved) around one of two
//  mechanical axes for how the middle gets populated:
//
//  - "derived-by-normalization" (`DJEntityQuery`, `LabelEntityQuery`,
//    `ReleaseEntityQuery`): there's no id-scoped fetch — the query always
//    pulls the full source and dedupes it down to one entity per normalized
//    key before resolving the caller's requested ids.
//  - "keyed-by-backend-id" (`ShowEntityQuery`, `VenueEntityQuery`,
//    `ConcertEntityQuery`, `PlaycutEntityQuery`): `identifiers` bridges into
//    the domain model's own id space first — directly via `EntityID.value`
//    for a `UInt64`-native id, or through a narrowing bridge like
//    `EntityID.venueID`/`.concertID` for an `Int`-native one — then the
//    source is asked only for those ids.
//
//  `ArtistEntityQuery` also derives by normalization but additionally
//  computes `playCount` and a representative display casing per group
//  (#646), so it keeps its own hand-written body rather than routing through
//  either helper below.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Resolves `identifiers` against entities derived by mapping every item
/// `source` returns through `makeEntity` — the "derived-by-normalization"
/// axis. There is no per-id fetch, so the full source is always pulled and
/// deduped. `makeEntity` both filters (return `nil` to skip a source item
/// with nothing to key on, e.g. a `Playcut` with no `labelName`) and builds
/// the entity. Preserves `identifiers`' order and drops ids nothing in
/// `source` produced. If two source items derive the same entity id, the
/// first one (in `source`'s order) wins — the query never traps.
func resolveEntities<Owner, Source, Entity>(
    identifiers: [EntityID<Owner>],
    from source: () async -> [Source],
    makeEntity: (Source) -> Entity?
) async -> [Entity] where Entity: Identifiable, Entity.ID == EntityID<Owner> {
    let byID = Dictionary(
        await source().compactMap(makeEntity).map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    return identifiers.compactMap { byID[$0] }
}

/// Resolves `identifiers` against entities fetched from `source` — the
/// "keyed-by-backend-id" axis. `rawID` bridges an `EntityID<Owner>` into the
/// domain model's own raw id space (`ShowMarker.id`, `Venue.id`,
/// `Concert.id`, `Playcut.id`); pass `{ $0.value }` for a `UInt64`-native id
/// that always succeeds, or a narrowing computed property like
/// `EntityID.venueID`/`.concertID` for an `Int`-native one that can fail.
/// `id` reads the matching raw id back off a fetched `Source` so it can be
/// looked up in the same space, and `makeEntity` builds (or fails to build)
/// the entity for that item. Preserves `identifiers`' order — dropping any
/// entry `rawID` couldn't bridge at all — and drops ids `source` couldn't
/// resolve or that failed to build an entity. If `source` returns duplicate
/// ids, the first one wins — the query never traps.
func resolveEntities<Owner, RawID: Hashable, Source, Entity>(
    identifiers: [EntityID<Owner>],
    rawID: (EntityID<Owner>) -> RawID?,
    from source: (_ rawIDs: [RawID]) async -> [Source],
    id: (Source) -> RawID,
    makeEntity: (Source) -> Entity?
) async -> [Entity] {
    let rawIDs = identifiers.compactMap(rawID)
    let byID = Dictionary(
        await source(rawIDs).compactMap { item in makeEntity(item).map { (id(item), $0) } },
        uniquingKeysWith: { first, _ in first }
    )
    return rawIDs.compactMap { byID[$0] }
}
