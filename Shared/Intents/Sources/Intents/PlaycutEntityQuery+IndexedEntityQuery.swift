//
//  PlaycutEntityQuery+IndexedEntityQuery.swift
//  Intents
//
//  iOS 27's `IndexedEntityQuery` lets Spotlight ask the app to re-donate
//  entities — row-by-row or wholesale — when it flags a problem with the
//  `wxyc.playcuts` index. Both handlers return `Void`: per Apple's docs, the
//  implementation fetches the entities and donates them again, rather than
//  returning a value. `CSSearchableIndexDescription` carries only a nullable
//  `protectionClass` — no index identity to dispatch on — so both handlers
//  donate straight to the one named index via `PlaycutReindexer`. Both also
//  report `SpotlightReindexRequested` through `AnalyticsService` (#445) before
//  resolving anything, so a reindex ask is visible in PostHog even when the
//  store has nothing to donate for it.
//
//  Gated to Swift 6.4 (the Xcode 27 beta toolchain): `IndexedEntityQuery` is
//  new in the iOS 27 AppIntents swiftinterface and isn't present in stable
//  Xcode 26.5/26.6. Stable builds skip this file entirely; `PlaycutEntityQuery`
//  itself (F1/F2/F3's production `entities(for:)` binding) is unaffected —
//  see `PlaycutEntityQuery.swift`, which declares the `@Dependency` stored
//  properties this extension reads (a Swift extension can't add stored
//  properties, so they can't live here).
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
#if !os(watchOS) && !os(tvOS)
import Analytics
import AppIntents
import CoreSpotlight
import Foundation
import Logger

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension PlaycutEntityQuery: IndexedEntityQuery {
    /// Chunk size for `reindexAllEntities`, matching
    /// `SpotlightDonationService.batchLimit` — a full-catalogue reindex (tens
    /// of thousands of rows across the 90-day history + rotation set) rides
    /// several donation calls instead of one.
    static let reindexChunkSize = 50

    /// Re-donates the identified playcuts to `wxyc.playcuts`.
    ///
    /// Ids `PlaycutHistoryStore` doesn't have are silently omitted — a
    /// Spotlight-requested reindex of a row the store no longer carries
    /// (evicted by the 90-day window, never seen this install) isn't an
    /// error, matching `entities(for:)`'s own drop-unknown-ids contract.
    /// Performs no network I/O: the store is a local cache and the system
    /// runtime asked for exactly this donation to happen synchronously
    /// within the handler.
    public func reindexEntities(
        for identifiers: [PlaycutID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        Log(.info, category: .general, "Spotlight requested reindexEntities(for:) — \(identifiers.count) id(s)")
        analytics.capture(SpotlightReindexRequested(kind: "single", rowCount: identifiers.count))
        let rawIDs = Set(identifiers.map(\.value))
        let playcuts = await historyStore.playcuts(ids: rawIDs)
        guard !playcuts.isEmpty else { return }
        try await reindexer.donate(playcuts.map(PlaycutEntity.init(playcut:)))
    }

    /// Re-donates `PlaycutHistoryStore`'s full indexable set — the last
    /// ~90 days of history plus the durable rotation set — in
    /// ``reindexChunkSize``-entity chunks.
    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let playcuts = await historyStore.allIndexable()
        Log(.info, category: .general, "Spotlight requested reindexAllEntities() — \(playcuts.count) playcut(s)")
        analytics.capture(SpotlightReindexRequested(kind: "all", rowCount: playcuts.count))
        guard !playcuts.isEmpty else { return }

        for start in stride(from: 0, to: playcuts.count, by: Self.reindexChunkSize) {
            let end = min(start + Self.reindexChunkSize, playcuts.count)
            let chunk = playcuts[start..<end].map(PlaycutEntity.init(playcut:))
            try await reindexer.donate(chunk)
        }
    }
}
#endif
#endif
