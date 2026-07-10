//
//  SpotlightIndexer.swift
//  AppServices
//
//  Seam that lets `SpotlightDonationService` be exercised in tests without
//  reaching for a live `CSSearchableIndex`. The production impl targets a
//  named `wxyc.playcuts` index; the SP-F1 identifier scheme (`PlaycutID`)
//  determines what a Spotlight tap resolves to via `OpenPlaycut`.
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

@preconcurrency import CoreSpotlight
import Foundation
import WXYCIntents

/// Injectable Spotlight indexing seam. The production impl forwards to
/// `CSSearchableIndex.indexAppEntities`; tests provide a recording double.
public protocol SpotlightIndexer: Sendable {
    /// Upserts `entities` into the `wxyc.playcuts` index.
    ///
    /// `priority` follows Apple's convention where a larger value asks the
    /// system to surface the item sooner. See ``SpotlightDonationService``
    /// for the two values in use (current-playcut vs. batch backfill).
    func indexPlaycuts(_ entities: [PlaycutEntity], priority: Int) async throws
}

/// Production `SpotlightIndexer` backed by a named `CSSearchableIndex`.
///
/// A named index (rather than `.default()`) scopes deletes and reindex hooks
/// to the WXYC playcut catalogue so an accidental reset can't nuke other
/// system-index entries the app might add later.
public struct CoreSpotlightIndexer: SpotlightIndexer {
    /// Name of the WXYC playcut index. Load-bearing: the SP-F3 reindex
    /// handlers will target this same name.
    public static let indexName = "wxyc.playcuts"

    private let index: CSSearchableIndex

    public init(indexName: String = Self.indexName) {
        self.index = CSSearchableIndex(name: indexName)
    }

    public func indexPlaycuts(_ entities: [PlaycutEntity], priority: Int) async throws {
        guard !entities.isEmpty else { return }
        try await index.indexAppEntities(entities, priority: priority)
    }
}

#endif
