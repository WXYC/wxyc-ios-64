//
//  ConcertSpotlightIndexer.swift
//  AppServices
//
//  The concert kind's Spotlight indexing path, targeting the named
//  `wxyc.concerts` index (`SpotlightIndexName.concerts`, WXYCIntents). It
//  shares `CoreSpotlightEntityIndexer<ConcertEntity>`'s stored index/name
//  with the playcut and artist kinds (`CoreSpotlightEntityIndexer.swift`) but
//  diverges in one load-bearing way, expressed here as a
//  `where Entity == ConcertEntity` extension rather than a parallel type
//  (#758): it does NOT go through
//  `CSSearchableIndex.indexAppEntities(_:priority:)`. That convenience
//  method builds each `CSSearchableItem` from `IndexedEntity.attributeSet`
//  alone, and `CSSearchableItemAttributeSet` has no `expirationDate` —
//  expiration lives on `CSSearchableItem` itself. Concerts need a
//  per-concert `expirationDate` (the OT-F2 crux — see
//  `ConcertSpotlightDonationService`), so this extension builds each
//  `CSSearchableItem` explicitly, associates the `ConcertEntity` onto it via
//  `CSSearchableItem.associateAppEntity(_:priority:)` (the documented path
//  for a caller that already builds its own `CSSearchableItem`s rather than
//  handing raw entities to `indexAppEntities`), sets `expirationDate`, and
//  indexes the items directly via `CSSearchableIndex.indexSearchableItems(_:)`.
//
//  `deleteConcerts(withIdentifiers:)` is the reconcile path's eviction half
//  (`CSSearchableIndex.deleteSearchableItems(withIdentifiers:)`), used when a
//  concert drops out of the fetched window before its date — a cancellation,
//  which expiration alone would miss (the show's date, and so its
//  `expirationDate`, is never reached).
//
//  Compiled out on watchOS and tvOS: `CoreSpotlight`, `IndexedEntity`, and
//  `CSSearchableItemAttributeSet` are all unavailable on those platforms, and
//  `WXYCIntents` (which vends `ConcertEntity`) isn't linked into either build
//  graph — see AppServices/Package.swift.
//
//  F3: `ConcertEntity` also conforms to `SpotlightReindexStrategy` (the
//  internal bridge to `SpotlightReindexer`, WXYCIntents) — see the extension
//  below, at the bottom of this file.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)

@preconcurrency import CoreSpotlight
import Concerts
import Foundation
import WXYCIntents

/// One concert's donation payload: the entity, the priority the OT-F2
/// reconcile pass derived for it (`ConcertSpotlightDonationService`'s
/// loved/stationRecommended/rest tiers), and the per-concert expiration
/// (`ConcertSpotlightDonationService`'s station-zone end-of-show-day).
public struct ConcertDonation: Sendable {
    public let entity: ConcertEntity
    public let priority: Int
    public let expirationDate: Date

    public init(entity: ConcertEntity, priority: Int, expirationDate: Date) {
        self.entity = entity
        self.priority = priority
        self.expirationDate = expirationDate
    }
}

/// Injectable Spotlight indexing seam for `ConcertEntity`. The production
/// impl forwards to a named `CSSearchableIndex`; tests provide a recording
/// double.
public protocol ConcertSpotlightIndexer: Sendable {
    /// Upserts `donations` into the `wxyc.concerts` index, one
    /// `CSSearchableItem` per donation carrying its own priority and
    /// `expirationDate`.
    func indexConcerts(_ donations: [ConcertDonation]) async throws

    /// Removes concerts with `identifiers` (`ConcertID.entityIdentifierString`
    /// values) from the `wxyc.concerts` index — the reconcile pass's
    /// eviction half for a concert that dropped out of the window before its
    /// date.
    func deleteConcerts(withIdentifiers identifiers: [String]) async throws
}

/// The concert kind's divergent indexing strategy (#758) — see the
/// file-level comment for why it can't reuse
/// `CoreSpotlightEntityIndexer.index(_:priority:)`.
///
/// A named index (rather than `.default()`) scopes deletes and reindex hooks
/// to the WXYC concert catalogue, matching the playcut/artist kinds'
/// rationale in `CoreSpotlightEntityIndexer.swift`.
extension CoreSpotlightEntityIndexer: ConcertSpotlightIndexer where Entity == ConcertEntity {
    public func indexConcerts(_ donations: [ConcertDonation]) async throws {
        guard !donations.isEmpty else { return }
        let items = donations.map { donation -> CSSearchableItem in
            let item = CSSearchableItem(
                uniqueIdentifier: donation.entity.id.entityIdentifierString,
                domainIdentifier: nil,
                attributeSet: donation.entity.attributeSet
            )
            item.associateAppEntity(donation.entity, priority: donation.priority)
            item.expirationDate = donation.expirationDate
            return item
        }
        try await searchableIndex.indexSearchableItems(items)
    }

    public func deleteConcerts(withIdentifiers identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await searchableIndex.deleteSearchableItems(withIdentifiers: identifiers)
    }
}

/// Builds the reindex donation batch: `ConcertSpotlightDonationService
/// .defaultPriority` for every concert (no liked-artist/station-cap context
/// exists on a Spotlight-triggered reindex — this isn't `ForYouShelf`-tiered
/// the way `reconcile`'s own donations are) and a freshly computed
/// `endOfShowDay` expiration per concert, reusing that service's constant and
/// helper so the two paths' notion of "when does a donated concert expire"
/// can never drift. A concert whose id can't bridge to `ConcertID` (see
/// `EntityID.init?(concertID:)`) is dropped, not fatal — defensive; never the
/// case for a real backend row.
///
/// Extracted as a pure, internal function (rather than inlined in
/// `ConcertEntity.reindexDonate(_:via:)` below) so it's unit-testable without
/// a real `CSSearchableIndex` round-trip, mirroring how
/// `ConcertSpotlightDonationServiceTests` exercises `reconcile`'s own
/// donation-building through `MockConcertSpotlightIndexer`.
extension CoreSpotlightEntityIndexer where Entity == ConcertEntity {
    static func reindexDonations(for concerts: [Concert]) -> [ConcertDonation] {
        concerts.compactMap { concert in
            guard let entity = ConcertEntity(concert: concert) else { return nil }
            return ConcertDonation(
                entity: entity,
                priority: ConcertSpotlightDonationService.defaultPriority,
                expirationDate: ConcertSpotlightDonationService.endOfShowDay(concert.startsOn)
            )
        }
    }
}

/// F3: the same named index doubles as the reindex handlers' donation seam
/// (`ConcertEntityQuery+IndexedEntityQuery`, WXYCIntents). `ConcertEntity`'s
/// `SpotlightReindexStrategy` conformance (see that protocol's doc comment in
/// `CoreSpotlightEntityIndexer.swift` for why this is a protocol conformance
/// rather than a second `where Entity == ConcertEntity` extension conforming
/// directly to `SpotlightReindexer`) mirrors the playcut kind's — the
/// reindexer strategy lives on the low-level indexer, not the higher-level
/// `ConcertSpotlightDonationService` reconcile orchestrator — but see
/// `SpotlightReindexer`'s doc comment for why: a reindex ask is a wholesale,
/// unconditional upsert, never a diff against `reconcile`'s persisted id set.
extension ConcertEntity: SpotlightReindexStrategy {
    public static func reindexDonate(_ concerts: [Concert], via indexer: CoreSpotlightEntityIndexer<ConcertEntity>) async throws {
        let donations = CoreSpotlightEntityIndexer<ConcertEntity>.reindexDonations(for: concerts)
        guard !donations.isEmpty else { return }
        try await indexer.indexConcerts(donations)
    }
}

#endif
