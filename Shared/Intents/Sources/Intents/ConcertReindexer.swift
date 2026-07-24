//
//  ConcertReindexer.swift
//  Intents
//
//  Donation seam through which the F3 `IndexedEntityQuery` reindex handlers
//  (`ConcertEntityQuery+IndexedEntityQuery.swift`) re-donate `Concert`s to
//  Spotlight, mirroring `PlaycutReindexer`. Declared here rather than
//  alongside the production `CoreSpotlightConcertIndexer` in AppServices for
//  the same reason as `PlaycutReindexer`: `ConcertEntityQuery` needs a seam
//  it can request via `@Dependency`, and AppServices depends on WXYCIntents —
//  not the other way around. `CoreSpotlightConcertIndexer` conforms to this
//  protocol (in addition to its existing `ConcertSpotlightIndexer`
//  conformance) so the F2 donation pipeline and the F3 reindex handlers share
//  one indexer instance and one named index.
//
//  Takes domain-model `Concert` values, not pre-built `ConcertEntity`s —
//  unlike `PlaycutReindexer.donate(_:)`, which takes `[PlaycutEntity]`
//  because `PlaycutEntity.init(playcut:)` can't fail. `ConcertEntity.
//  init?(concert:)` can fail (a negative id), and a per-concert
//  `expirationDate` has to be derived from `Concert.startsOn`, so the
//  conformer builds and filters entities itself — the same shape
//  `ConcertSpotlightDonationService` already uses for its own donations.
//
//  Deliberately NOT a diff against `ConcertSpotlightDonationService`'s
//  persisted id set: `donate(_:)` is a wholesale, unconditional upsert of
//  whatever `concerts` the caller hands it, with no eviction of anything
//  absent from that list. A Spotlight reindex ask means "these concerts are
//  current, tell the index now" — not "here's what changed since the last
//  background reconcile." Folding this into `reconcile(window:...)`'s
//  diff/eviction bookkeeping would misfire on both reindex paths: for
//  `reindexEntities(for:)`'s small per-id batch, `reconcile` would read
//  every previously-persisted concert absent from that batch as departed and
//  evict the rest of the index; for `reindexAllEntities()`, `reconcile` only
//  upserts ids newly absent from the persisted set, so an already-persisted
//  concert's `expirationDate` would never actually refresh — defeating the
//  "re-donate with fresh expiry" contract a full reindex ask needs.
//
//  Free of CoreSpotlight and AppIntents symbols so it compiles on every
//  platform WXYCIntents ships to, including watchOS and tvOS, where
//  CoreSpotlight is unavailable — matching `PlaycutReindexer`.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Foundation

/// Re-donates `Concert` values to Spotlight for the F3 reindex-recovery
/// handlers.
///
/// `CoreSpotlightConcertIndexer` (AppServices) is the production conformer;
/// tests use a recording spy.
public protocol ConcertReindexer: Sendable {
    func donate(_ concerts: [Concert]) async throws
}
