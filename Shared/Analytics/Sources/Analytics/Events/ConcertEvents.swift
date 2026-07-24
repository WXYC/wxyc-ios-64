//
//  ConcertEvents.swift
//  Analytics
//
//  Structured analytics for the OT-F2/F3 concert Spotlight pipeline
//  (`wxyc.concerts`) — the concert analog of `SpotlightEvents.swift`'s
//  playcut/artist donation events (#445, mirrored here for #631/OT-Q1). Lets
//  us see in PostHog whether the concert index is being kept warm: how many
//  concerts are donated per reconcile pass and at what priority tier, how
//  many are evicted when they drop out of the curated window (e.g. a
//  cancellation before its date), and whether iOS 27's reindex-recovery loop
//  is asking for concerts back. Identity-free per the On Tour privacy
//  invariant (`OnTourEvents.swift`): no event here ever carries a concert
//  id, artist id, or artist name — only counts and the non-identifying
//  priority tier a batch donated at.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Event fired when `ConcertSpotlightDonationService.reconcile` successfully
/// upserts a batch of concerts into `wxyc.concerts`. `batchSize` is the
/// number of concerts sent at that priority; `priorityTier` is the
/// `ForYouShelf`-derived tier the batch was indexed at — `"loved"`,
/// `"stationRecommended"`, or `"default"` (the rest tier, mirroring
/// `ConcertSpotlightDonationService.defaultPriority`). A single reconcile
/// pass fires one event per tier represented among its newly-donated
/// concerts, so a mixed batch (some loved, some default) is visible as
/// separate per-tier counts rather than one opaque total. Never carries a
/// concert or artist id.
@AnalyticsEvent
public struct ConcertsDonated {
    public let batchSize: Int
    public let priorityTier: String

    public init(batchSize: Int, priorityTier: String) {
        self.batchSize = batchSize
        self.priorityTier = priorityTier
    }
}

/// Event fired when `ConcertSpotlightDonationService.reconcile` successfully
/// evicts concerts that dropped out of the fetched window before their show
/// date — the cancellation case that expiry alone would miss (see
/// `ConcertSpotlightDonationService`'s doc comment). `evictedCount` is the
/// number of concerts removed from `wxyc.concerts` in that call. Never
/// carries which concerts were evicted.
@AnalyticsEvent
public struct ConcertsEvicted {
    public let evictedCount: Int

    public init(evictedCount: Int) {
        self.evictedCount = evictedCount
    }
}

/// Event fired when iOS 27's `IndexedEntityQuery` reindex-recovery loop asks
/// the app to re-donate concerts to `wxyc.concerts`
/// (`ConcertEntityQuery+IndexedEntityQuery`, OT-F3). `kind` is `"single"`
/// (`reindexEntities(for:)`, a targeted set of ids) or `"all"`
/// (`reindexAllEntities()`, the full curated window). `rowCount` differs by
/// `kind`, matching `SpotlightReindexRequested`'s playcut convention: for
/// `"single"` it's the number of ids Spotlight asked for (recorded before
/// resolution, so the ask is visible even when nothing resolves); for
/// `"all"` it's the number of concerts the handler fetched and re-donated. A
/// concert-specific type rather than a reuse of `SpotlightReindexRequested`
/// so concert reindex volume is queryable in PostHog without disambiguating
/// it from the unrelated playcut/artist reindex traffic that shares the same
/// `kind` vocabulary. Never carries a concert or artist id.
@AnalyticsEvent
public struct ConcertReindexRequested {
    public let kind: String
    public let rowCount: Int

    public init(kind: String, rowCount: Int) {
        self.kind = kind
        self.rowCount = rowCount
    }
}
