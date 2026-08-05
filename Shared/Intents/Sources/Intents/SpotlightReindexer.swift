//
//  SpotlightReindexer.swift
//  Intents
//
//  Donation seam through which the F3 `IndexedEntityQuery` reindex handlers
//  (`PlaycutEntityQuery+IndexedEntityQuery.swift`,
//  `ConcertEntityQuery+IndexedEntityQuery.swift`) re-donate entities to
//  Spotlight. One generic, associated-type protocol replaces the two
//  near-identical per-kind protocols this package used to declare
//  (`PlaycutReindexer`, `ConcertReindexer`) — #758.
//
//  The associated `Source` type is deliberately not constrained to
//  `IndexedEntity`/`AppEntity`: playcuts hand over pre-built `PlaycutEntity`
//  values (`PlaycutEntity.init(playcut:)` can't fail), but concerts hand over
//  domain-model `Concert` values instead of pre-built `ConcertEntity`s,
//  because `ConcertEntity.init?(concert:)` can fail (a negative id) and a
//  per-concert `expirationDate` has to be derived from `Concert.startsOn` —
//  the conformer builds and filters entities itself, the same shape
//  `ConcertSpotlightDonationService` already uses for its own donations.
//  `donate(_:)` is always a wholesale, unconditional upsert of whatever the
//  caller hands it, never a diff against a persisted id set: a Spotlight
//  reindex ask means "these are current, tell the index now," not "here's
//  what changed since the last background reconcile." Folding this into
//  `ConcertSpotlightDonationService.reconcile(window:...)`'s diff/eviction
//  bookkeeping would misfire on both reindex paths — see the concert F3
//  reindex extension in `ConcertEntityQuery+IndexedEntityQuery.swift` for
//  the two concrete failure modes.
//
//  Declared here — not alongside the production
//  `CoreSpotlightEntityIndexer` conformances in AppServices — because
//  `PlaycutEntityQuery`/`ConcertEntityQuery` need a seam they can request via
//  `@Dependency`, and AppServices depends on WXYCIntents, not the other way
//  around. `CoreSpotlightEntityIndexer<PlaycutEntity>`/
//  `CoreSpotlightEntityIndexer<ConcertEntity>` conform to this protocol (in
//  addition to their existing `SpotlightIndexer`/`ConcertSpotlightIndexer`
//  conformances) so the F2 donation pipelines and the F3 reindex handlers
//  share one indexer instance and one named index per entity kind.
//
//  Free of CoreSpotlight and AppIntents `IndexedEntity` symbols so it
//  compiles on every platform WXYCIntents ships to, including watchOS and
//  tvOS, where CoreSpotlight is unavailable.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Re-donates `Source` values to Spotlight for the F3 reindex-recovery
/// handlers. `Source` is `PlaycutEntity` for the playcut kind and `Concert`
/// for the concert kind — see the file-level comment for why the two kinds'
/// input shapes differ.
///
/// `CoreSpotlightEntityIndexer<PlaycutEntity>`/`CoreSpotlightEntityIndexer
/// <ConcertEntity>` (AppServices) are the production conformers; tests use a
/// recording spy.
public protocol SpotlightReindexer<Source>: Sendable {
    associatedtype Source
    func donate(_ items: [Source]) async throws
}
