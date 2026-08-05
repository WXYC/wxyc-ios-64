//
//  CoreSpotlightEntityIndexer.swift
//  AppServices
//
//  Seam that lets `SpotlightDonationService` be exercised in tests without
//  reaching for a live `CSSearchableIndex`. The production impl targets a
//  named `wxyc.playcuts` index; the SP-F1 identifier scheme (`PlaycutID`)
//  determines what a Spotlight tap resolves to via `OpenPlaycut`.
//
//  `ArtistSpotlightIndexer` (C6) mirrors this same seam shape against the
//  separate named `wxyc.artists` index — a distinct protocol rather than a
//  second method on `SpotlightIndexer` so the two entity kinds' named
//  indexes can never be conflated at a callsite.
//
//  `CoreSpotlightEntityIndexer<Entity: IndexedEntity>` (#758) is the single
//  generic struct that backs both seam protocols' production conformances
//  (and, via `ConcertSpotlightIndexer.swift`'s `where Entity == ConcertEntity`
//  extension, the concert kind's divergent indexing path too). It replaces
//  three near-identical concrete structs — `CoreSpotlightIndexer`,
//  `CoreSpotlightArtistIndexer` (both previously declared in this file), and
//  `CoreSpotlightConcertIndexer` (previously in `ConcertSpotlightIndexer.swift`)
//  — that differed only in their entity type and named index. Adding a
//  fourth entity kind now needs one instantiation
//  (`CoreSpotlightEntityIndexer<NewEntity>(indexName:)`), not a new struct.
//
//  Compiled out on watchOS and tvOS: `CoreSpotlight`, `IndexedEntity`,
//  and `CSSearchableItemAttributeSet` are all unavailable on those
//  platforms, and `WXYCIntents` (which vends `PlaycutEntity`) isn't
//  linked into either build graph — see AppServices/Package.swift.
//
//  Created by Jake Bromberg on 07/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)

import AppIntents
@preconcurrency import CoreSpotlight
import Foundation
import WXYCIntents

/// Injectable Spotlight indexing seam for `PlaycutEntity`. The production
/// impl forwards to `CSSearchableIndex.indexAppEntities`; tests provide a
/// recording double.
public protocol SpotlightIndexer: Sendable {
    /// Upserts `entities` into the `wxyc.playcuts` index.
    ///
    /// `priority` follows Apple's convention where a larger value asks the
    /// system to surface the item sooner. See ``SpotlightDonationService``
    /// for the two values in use (current-playcut vs. batch backfill).
    func indexPlaycuts(_ entities: [PlaycutEntity], priority: Int) async throws
}

/// Injectable Spotlight indexing seam for `ArtistEntity`, mirroring
/// `SpotlightIndexer`. The production impl forwards to
/// `CSSearchableIndex.indexAppEntities` against the `wxyc.artists` index;
/// tests provide a recording double.
public protocol ArtistSpotlightIndexer: Sendable {
    /// Upserts `entities` into the `wxyc.artists` index.
    ///
    /// `priority` follows the same convention as ``SpotlightIndexer/indexPlaycuts(_:priority:)``.
    /// `SpotlightDonationService.donateArtists(from:)` sends `batchPriority`
    /// — artist donation piggybacks on the same background-refresh
    /// cadence as the playcut batch, with no elevated per-tick path.
    func indexArtists(_ entities: [ArtistEntity], priority: Int) async throws
}

/// Generic production Spotlight indexer backed by a named `CSSearchableIndex`,
/// parameterized by the `IndexedEntity` kind it indexes (#758).
///
/// A named index (rather than `.default()`) scopes deletes and reindex hooks
/// to one entity kind's catalogue so an accidental reset can't nuke other
/// system-index entries the app might add later — the rationale each of the
/// three predecessor structs carried individually.
///
/// The concert kind's genuinely divergent path — a per-item `expirationDate`,
/// which `CSSearchableItemAttributeSet` has no field for, so it has to be set
/// on a directly-built `CSSearchableItem` rather than going through
/// `indexAppEntities` — lives in the `where Entity == ConcertEntity`
/// extension in `ConcertSpotlightIndexer.swift`, a strategy on this generic
/// type rather than a parallel type.
public struct CoreSpotlightEntityIndexer<Entity: IndexedEntity>: Sendable {
    /// The named index this instance targets, e.g. `SpotlightIndexName.playcuts`.
    public let indexName: String

    /// `internal` (not `private`) so the `where Entity == ConcertEntity`
    /// extension declared in `ConcertSpotlightIndexer.swift` — a separate
    /// file — can build and index `CSSearchableItem`s directly against the
    /// same underlying index.
    let searchableIndex: CSSearchableIndex

    public init(indexName: String) {
        self.indexName = indexName
        self.searchableIndex = CSSearchableIndex(name: indexName)
    }

    /// Upserts `entities` via `CSSearchableIndex.indexAppEntities` — the
    /// shared body every non-concert entity kind's seam-protocol conformance
    /// below forwards to.
    public func index(_ entities: [Entity], priority: Int) async throws {
        guard !entities.isEmpty else { return }
        try await searchableIndex.indexAppEntities(entities, priority: priority)
    }
}

extension CoreSpotlightEntityIndexer: SpotlightIndexer where Entity == PlaycutEntity {
    public func indexPlaycuts(_ entities: [PlaycutEntity], priority: Int) async throws {
        try await index(entities, priority: priority)
    }
}

extension CoreSpotlightEntityIndexer: ArtistSpotlightIndexer where Entity == ArtistEntity {
    public func indexArtists(_ entities: [ArtistEntity], priority: Int) async throws {
        try await index(entities, priority: priority)
    }
}

/// Bridges an `IndexedEntity` kind's own reindex-donation shape to
/// `CoreSpotlightEntityIndexer`'s `SpotlightReindexer` (WXYCIntents)
/// conformance.
///
/// Swift forbids two separate `where Entity == X` / `where Entity == Y`
/// extensions of one generic type conforming to the *same* protocol, even
/// when the where-clauses are mutually exclusive ("conflicting conformance
/// of 'CoreSpotlightEntityIndexer<Entity>' to protocol 'SpotlightReindexer';
/// there cannot be more than one conformance, even with different
/// conditional bounds"). So `CoreSpotlightEntityIndexer` declares its
/// `SpotlightReindexer` conformance exactly once below, conditioned on this
/// one shared constraint, and dispatches to each conforming entity kind's own
/// static `reindexDonate(_:via:)` — the playcut kind's below, the concert
/// kind's in `ConcertSpotlightIndexer.swift`. A third entity kind that never
/// needs F3 reindex support doesn't conform to this at all; one that does
/// adds one small conformance here, not a new protocol.
public protocol SpotlightReindexStrategy: IndexedEntity {
    associatedtype ReindexSource
    static func reindexDonate(_ source: [ReindexSource], via indexer: CoreSpotlightEntityIndexer<Self>) async throws
}

extension CoreSpotlightEntityIndexer: SpotlightReindexer where Entity: SpotlightReindexStrategy {
    public typealias Source = Entity.ReindexSource

    public func donate(_ items: [Source]) async throws {
        try await Entity.reindexDonate(items, via: self)
    }
}

/// F3: the same named index doubles as the reindex handlers' donation seam.
/// `SpotlightDonationService.batchPriority` matches the priority the F2
/// background-refresh batch path already uses — a reindex is functionally a
/// backfill, not an elevated-priority "on air now" surface.
extension PlaycutEntity: SpotlightReindexStrategy {
    public static func reindexDonate(_ entities: [PlaycutEntity], via indexer: CoreSpotlightEntityIndexer<PlaycutEntity>) async throws {
        try await indexer.indexPlaycuts(entities, priority: SpotlightDonationService.batchPriority)
    }
}

#endif
