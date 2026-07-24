//
//  SpotlightEvents.swift
//  Analytics
//
//  Structured analytics for the Spotlight donation pipeline (#445, Q2 of
//  docs/ideas/spotlight-app-entities.md). Lets us see in PostHog whether the
//  `wxyc.playcuts` / `wxyc.artists` indexes are being kept warm, and whether
//  the system's iOS 27 reindex-recovery loop is firing. No listener PII ever
//  rides along — only playcut ids (public catalogue identifiers, not taste
//  data), batch sizes, and coarse error kinds.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Event fired when a Spotlight donation call (recent-batch or artist-batch)
/// successfully indexes its entities. `playcutID` is the batch's
/// representative playcut id — the `.id` of the input playcut with the
/// highest `chronOrderID` — so a donation can be correlated back to a
/// flowsheet tick; `batchSize` is the number of entities sent; `priorityTier`
/// is the Spotlight priority the batch was indexed at (see
/// `SpotlightDonationService.currentPlaycutPriority` /
/// `.batchPriority`); `kind` is `"playcuts"` (`donateRecentPlaycuts`, feeds
/// `wxyc.playcuts`) or `"artists"` (`donateArtists`, feeds `wxyc.artists`) —
/// without it, the two capture sites are indistinguishable in PostHog
/// whenever they happen to share a `batchSize` (#639).
@AnalyticsEvent
public struct SpotlightDonated {
    public let playcutID: String
    public let batchSize: Int
    public let priorityTier: Int
    public let kind: String

    public init(playcutID: String, batchSize: Int, priorityTier: Int, kind: String) {
        self.playcutID = playcutID
        self.batchSize = batchSize
        self.priorityTier = priorityTier
        self.kind = kind
    }
}

/// Event fired when a Spotlight donation call's indexer throws. `errorKind`
/// is a coarse categorization (the thrown error's `NSError` domain) rather
/// than the full error description, so the event never carries free-form
/// text that might vary by locale or wrap incidental detail. `batchSize` is
/// the number of entities the failed call attempted to send.
@AnalyticsEvent
public struct SpotlightDonationFailed {
    public let errorKind: String
    public let batchSize: Int

    public init(errorKind: String, batchSize: Int) {
        self.errorKind = errorKind
        self.batchSize = batchSize
    }
}

/// Event fired when iOS 27's `IndexedEntityQuery` reindex-recovery loop asks
/// the app to re-donate entities to `wxyc.playcuts` (SP-F3). `kind` is
/// `"single"` (`reindexEntities(for:)`, a targeted set of ids) or `"all"`
/// (`reindexAllEntities()`, the full indexable set). `rowCount` differs in
/// what it counts by `kind`: for `"single"` it's the number of ids Spotlight
/// asked for (recorded before store resolution, so the ask is visible even
/// when nothing resolves); for `"all"` it's the number of playcuts the
/// handler resolved and re-donated.
@AnalyticsEvent
public struct SpotlightReindexRequested {
    public let kind: String
    public let rowCount: Int

    public init(kind: String, rowCount: Int) {
        self.kind = kind
        self.rowCount = rowCount
    }
}
