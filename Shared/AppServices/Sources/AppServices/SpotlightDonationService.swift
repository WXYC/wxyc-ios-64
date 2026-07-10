//
//  SpotlightDonationService.swift
//  AppServices
//
//  Feeds the `wxyc.playcuts` Spotlight content index. Two donation paths
//  share one watermark:
//
//  * `donateCurrentPlaycut(_:)` fires from a `NowPlayingService` subscription
//    on every tick — a single entity at elevated priority so Spotlight and
//    Siri surface the currently-airing track sooner.
//  * `donateRecentPlaycuts(_:)` fires from the background-refresh handler
//    with the whole recent playlist — up to 50 unseen playcuts at normal
//    priority, so a cold catalogue rebuilds without exhausting BGAppRefresh
//    budget in a single tick.
//
//  The watermark ("last successfully-donated chronOrderID" from the batch
//  path) lives in `DefaultsStorage` so the catalogue keeps advancing across
//  launches. Only `donateRecentPlaycuts` moves the watermark — the per-tick
//  path is idempotent-upsert-only so it can't skip playcuts the batch has
//  not yet seen.
//
//  This file is compiled out on watchOS and tvOS: `CoreSpotlight`,
//  `IndexedEntity`, and `CSSearchableItemAttributeSet` are all
//  unavailable on those platforms, and `WXYCIntents` isn't linked into
//  either build graph (see AppServices/Package.swift for the
//  platform-gated dependency). Callers on iOS/macOS instantiate the
//  service directly.
//
//  Created by Jake Bromberg on 07/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)

import Caching
import Foundation
import Logger
import Playlist
import WXYCIntents

public actor SpotlightDonationService: Sendable {

    // MARK: - Constants

    /// UserDefaults key for the "last successfully-donated chronOrderID".
    /// Stored as a decimal `String` because `chronOrderID` is `UInt64` and
    /// `DefaultsStorage.integer(forKey:)` returns a signed `Int`.
    public static let watermarkKey = "spotlight.playcuts.watermark"

    /// Priority for a per-tick current-playcut donation. Deliberately above
    /// the batch value so Spotlight surfaces the on-air track sooner than a
    /// backfilled item from earlier in the show.
    public static let currentPlaycutPriority = 500

    /// Priority for the background-refresh batch. Apple's docs use `100` as
    /// the normal-priority reference; we match it.
    public static let batchPriority = 100

    /// Cap on entities per batch. Anchored to the background-refresh budget
    /// (`docs/configuration.md`) and to Playlist's typical `n=50` fetch
    /// window — sending more per tick either wastes bandwidth or overruns
    /// BGAppRefresh's ~30s wall clock.
    public static let batchLimit = 50

    // MARK: - Dependencies

    private let storage: DefaultsStorage
    private let indexer: SpotlightIndexer

    // MARK: - Init

    public init(storage: DefaultsStorage, indexer: SpotlightIndexer) {
        self.storage = storage
        self.indexer = indexer
    }

    // MARK: - Public API

    /// Upsert the current playcut into `wxyc.playcuts` at elevated priority.
    ///
    /// Called from a `NowPlayingService` subscription on every tick. This
    /// path deliberately does NOT advance the batch watermark: on a cold
    /// launch the tick fires with the newest playcut (`playlist.playcuts.first`)
    /// before the background-refresh path has a chance to run, and advancing
    /// the watermark here would filter every unseen historical entry — the
    /// entire initial 50-row window on a fresh install — out of the next
    /// batch donation. Spotlight upserts are idempotent, so a later batch
    /// re-donating the current playcut is a no-op.
    public func donateCurrentPlaycut(_ playcut: Playcut) async {
        let entity = PlaycutEntity(playcut: playcut)
        do {
            try await indexer.indexPlaycuts([entity], priority: Self.currentPlaycutPriority)
        } catch {
            Log(.warning, category: .general, "Spotlight donation failed for playcut \(playcut.id): \(error)")
        }
    }

    /// Batch-upsert playcuts newer than the persisted watermark.
    ///
    /// Called after a background refresh completes with the freshly-fetched
    /// playlist. Stale playcuts (`chronOrderID <= watermark`) are dropped,
    /// the remainder is sorted ascending and capped at ``batchLimit``. On a
    /// successful indexer return the watermark advances to the largest
    /// `chronOrderID` in the sent batch; on failure it stays put and the
    /// next tick retries the same range.
    public func donateRecentPlaycuts(_ playcuts: [Playcut]) async {
        let watermark = currentWatermark
        let batch = playcuts
            .filter { $0.chronOrderID > watermark }
            .sorted { $0.chronOrderID < $1.chronOrderID }
            .prefix(Self.batchLimit)

        guard let highestID = batch.last?.chronOrderID else { return }

        let entities = batch.map(PlaycutEntity.init(playcut:))
        do {
            try await indexer.indexPlaycuts(entities, priority: Self.batchPriority)
            advanceWatermarkIfNewer(highestID)
        } catch {
            Log(.warning, category: .general, "Spotlight batch donation failed (\(entities.count) playcuts): \(error)")
        }
    }

    // MARK: - Watermark

    private var currentWatermark: UInt64 {
        storage.string(forKey: Self.watermarkKey).flatMap(UInt64.init) ?? 0
    }

    private func advanceWatermarkIfNewer(_ candidate: UInt64) {
        guard candidate > currentWatermark else { return }
        storage.set(String(candidate), forKey: Self.watermarkKey)
    }
}

#endif
