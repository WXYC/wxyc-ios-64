//
//  SpotlightDonationService.swift
//  AppServices
//
//  Feeds the `wxyc.playcuts` Spotlight content index. Three donation paths
//  share one watermark:
//
//  * `donateCurrentPlaycut(_:)` fires from a `PlaylistService.updates()`
//    subscription on every tick — a single entity at elevated priority so
//    Spotlight and Siri surface the currently-airing track sooner. The
//    actor dedups consecutive identical playcuts internally so metadata
//    re-broadcasts don't burn XPC round-trips.
//  * `donateRecentPlaycuts(_:)` fires from the same subscription (and from
//    `BackgroundRefreshController` as a belt-and-suspenders guarantee that
//    the batch completes inside the BGAppRefresh wall-clock window) with
//    the whole recent playlist — up to 50 unseen playcuts at normal
//    priority, so a cold catalogue rebuilds without exhausting BGAppRefresh
//    budget in a single tick.
//  * `observeMetadataEnrichment(from:)` consumes
//    `PlaylistService.terminalMetadataTransitions()` and re-donates a single
//    already-donated row through `handleMetadataEnrichment(for:)` when its
//    `metadata_status` lands in a terminal enriched state — issue #443.
//
//  The watermark ("last successfully-donated chronOrderID" from the batch
//  path) lives in `DefaultsStorage` so the catalogue keeps advancing across
//  launches. Only `donateRecentPlaycuts` moves the watermark — the per-tick
//  and enrichment-re-donation paths are idempotent-upsert-only so neither
//  can skip playcuts the batch has not yet seen.
//
//  A fourth path, `donateArtists(from:)` (C6), feeds a separate
//  `wxyc.artists` index. It shares no watermark with the playcut paths
//  above — it dedups whatever playcuts the caller hands it (typically the
//  same batch passed to `donateRecentPlaycuts`) down to one `ArtistEntity`
//  per normalized artist name, via `ArtistEntityQuery`'s grouping, and
//  upserts at `batchPriority`. Re-donating an artist with an unchanged play
//  count is a cheap no-op server-side, so no separate waterline is needed.
//
//  `donateRecentPlaycuts(_:)` and `donateArtists(from:)` report `SpotlightDonated`
//  / `SpotlightDonationFailed` through the injected `AnalyticsService` (#445) so
//  we can see in PostHog whether the two indexes are being kept warm. Both events
//  carry only playcut ids, batch sizes, and coarse error kinds — no listener PII.
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

import Analytics
import Caching
import Foundation
import Logger
import Playlist
import WXYCIntents

/// Source of terminal metadata-enrichment transitions for
/// ``SpotlightDonationService/observeMetadataEnrichment(from:)``.
///
/// `PlaylistService` conforms via the extension below. Tests inject a
/// lightweight double so `SpotlightDonationService`'s re-donation gating can
/// be exercised without a live `PlaylistService` (network fetcher, cache
/// coordinator, etc.).
public protocol MetadataEnrichmentTransitionsSource: Sendable {
    /// See `PlaylistService.terminalMetadataTransitions()`.
    func terminalMetadataTransitions() -> AsyncStream<Playcut>
}

extension PlaylistService: MetadataEnrichmentTransitionsSource {}

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
    private let artistIndexer: ArtistSpotlightIndexer
    private let analytics: AnalyticsService

    // MARK: - State

    /// The last playcut successfully donated by `donateCurrentPlaycut`, used
    /// to skip redundant XPC round-trips when `PlaylistService` re-broadcasts
    /// an unchanged top playcut. Playcut equality is field-wise (see
    /// `PlaylistEntry`), so a metadata-enrichment landing that actually
    /// changes `artworkURL` / `spotifyURL` / genres still passes the guard
    /// and refreshes the Spotlight attribute set.
    private var lastDonatedCurrentPlaycut: Playcut?

    // MARK: - Init

    public init(
        storage: DefaultsStorage,
        indexer: SpotlightIndexer,
        artistIndexer: ArtistSpotlightIndexer = CoreSpotlightArtistIndexer(),
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared
    ) {
        self.storage = storage
        self.indexer = indexer
        self.artistIndexer = artistIndexer
        self.analytics = analytics
    }

    // MARK: - Public API

    /// Upsert the current playcut into `wxyc.playcuts` at elevated priority.
    ///
    /// Called from a `PlaylistService.updates()` subscription on every tick.
    /// This path deliberately does NOT advance the batch watermark: on a
    /// cold launch the tick fires with the newest playcut
    /// (`playlist.playcuts.first`) before the background-refresh path has a
    /// chance to run, and advancing the watermark here would filter every
    /// unseen historical entry — the entire initial 50-row window on a
    /// fresh install — out of the next batch donation. Spotlight upserts
    /// are idempotent, so a later batch re-donating the current playcut is
    /// a no-op.
    ///
    /// A short-circuit dedup skips the XPC round-trip when the incoming
    /// playcut is byte-identical to the last successfully indexed one — the
    /// common case when `PlaylistService` re-broadcasts a downstream
    /// enrichment that didn't touch `playcuts.first`.
    public func donateCurrentPlaycut(_ playcut: Playcut) async {
        guard playcut != lastDonatedCurrentPlaycut else { return }
        let entity = PlaycutEntity(playcut: playcut)
        do {
            try await indexer.indexPlaycuts([entity], priority: Self.currentPlaycutPriority)
            lastDonatedCurrentPlaycut = playcut
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

        // The playcut `.id` (not chronOrderID, which only orders the batch and
        // drives the watermark below) of the newest row in the batch — the
        // representative id SpotlightDonated reports.
        let representativeID = batch.last?.id ?? 0

        let entities = batch.map(PlaycutEntity.init(playcut:))
        do {
            try await indexer.indexPlaycuts(entities, priority: Self.batchPriority)
            advanceWatermarkIfNewer(highestID)
            analytics.capture(SpotlightDonated(playcutID: String(representativeID), batchSize: entities.count, priorityTier: Self.batchPriority, kind: "playcuts"))
        } catch {
            Log(.warning, category: .general, "Spotlight batch donation failed (\(entities.count) playcuts): \(error)")
            analytics.capture(SpotlightDonationFailed(errorKind: (error as NSError).domain, batchSize: entities.count))
        }
    }

    /// Re-donates a single playcut whose `metadataStatus` just transitioned
    /// to a terminal enrichment state (see
    /// `PlaylistService.terminalMetadataTransitions()`), but only when the
    /// row was donated previously — either by the batch path
    /// (`chronOrderID <= watermark`) or by the per-tick path (it's the
    /// current on-air playcut). `indexAppEntities` upserts on identifier, so
    /// this is a free no-op server-side; the guard exists so we don't spend
    /// an XPC round-trip on a row Spotlight has never indexed — the next
    /// batch/tick donation picks it up with the enriched fields already
    /// inline (issue #443).
    ///
    /// When the enriching row is the current on-air playcut, the per-tick
    /// path (`donateCurrentPlaycut`) also upserts it this same cycle — the two
    /// donation tasks race on the actor with nondeterministic ordering. A
    /// second guard skips the round-trip when the per-tick path already sent
    /// this exact entity; and when this path wins the race and donates the
    /// on-air entity, it refreshes `lastDonatedCurrentPlaycut` so the trailing
    /// per-tick call dedups. Either way the on-air playcut is donated once per
    /// enrichment landing, not twice.
    public func handleMetadataEnrichment(for playcut: Playcut) async {
        guard wasPreviouslyDonated(playcut) else { return }
        guard playcut != lastDonatedCurrentPlaycut else { return }

        let entity = PlaycutEntity(playcut: playcut)
        do {
            try await indexer.indexPlaycuts([entity], priority: Self.batchPriority)
            // If this is the on-air playcut, share the watermark of "already
            // donated this exact entity" with the per-tick path so it dedups.
            if playcut.id == lastDonatedCurrentPlaycut?.id {
                lastDonatedCurrentPlaycut = playcut
            }
        } catch {
            Log(.warning, category: .general, "Spotlight re-donation failed for playcut \(playcut.id): \(error)")
        }
    }

    /// Batch-upsert `ArtistEntity` values derived from `playcuts` into the
    /// `wxyc.artists` index (C6).
    ///
    /// Groups `playcuts` by normalized artist name — the same dedup key
    /// `ArtistEntityQuery`/`ArtistEntity` use elsewhere — so name variations
    /// ("Stereolab" vs. "Stereolab feat. …", casing, whitespace) collapse to
    /// one entity carrying the group's play count as of this call. Each
    /// entity's *display* name is a representative original casing drawn
    /// from the group (see `WXYCIntents.representativeName(in:)`, shared
    /// with `ArtistEntityQuery.entities(for:)` as of #646), not the
    /// normalized key itself — issue #640. The resulting entities are capped
    /// at ``batchLimit`` (mirroring `donateRecentPlaycuts`'s bound on
    /// background-refresh work) and sent at ``batchPriority``. No watermark:
    /// unlike the playcut batch, this path always re-derives entities fresh
    /// from whatever playcuts the caller passes, so play counts never go
    /// stale, and a re-donation of an unchanged count is a free upsert
    /// server-side.
    public func donateArtists(from playcuts: [Playcut]) async {
        let grouped = Dictionary(grouping: playcuts) { normalizedEntityKey($0.artistName) }
        let entities = grouped
            .map { _, group in
                ArtistEntity(artistName: representativeName(in: group), playCount: group.count)
            }
            .prefix(Self.batchLimit)

        guard !entities.isEmpty else { return }

        // Representative playcut id for correlation with the flowsheet tick
        // that produced this artist batch — the `.id` of the input playcut
        // with the highest chronOrderID, matching donateRecentPlaycuts's
        // newest-row-in-the-batch convention even though this path shares no
        // watermark of its own.
        let representativeID = playcuts.max { $0.chronOrderID < $1.chronOrderID }?.id ?? 0

        do {
            try await artistIndexer.indexArtists(Array(entities), priority: Self.batchPriority)
            analytics.capture(SpotlightDonated(playcutID: String(representativeID), batchSize: entities.count, priorityTier: Self.batchPriority, kind: "artists"))
        } catch {
            Log(.warning, category: .general, "Spotlight artist donation failed (\(entities.count) artists): \(error)")
            analytics.capture(SpotlightDonationFailed(errorKind: (error as NSError).domain, batchSize: entities.count))
        }
    }

    /// Single background-refresh / foreground-tick batch entry point.
    ///
    /// Feeds the same `playcuts` window to both the `wxyc.playcuts` batch
    /// (``donateRecentPlaycuts(_:)``) and the `wxyc.artists` batch
    /// (``donateArtists(from:)``) so the two indexes advance together on the
    /// same tick from the same source. `BackgroundRefreshController.handleRefresh`
    /// and `Singletonia.startSpotlightDonation` both call this rather than the
    /// two methods separately, so a caller can't donate playcuts while
    /// silently dropping artists (or vice versa) — the C6 artist index is
    /// populated on exactly the ticks the playcut index already was.
    ///
    /// Playcuts donate first: on a cold-install tick that lands close to the
    /// BGAppRefresh budget, the playcut catalogue (the primary Spotlight
    /// surface) takes precedence over the derived artist rows.
    public func donateBatch(from playcuts: [Playcut]) async {
        await donateRecentPlaycuts(playcuts)
        await donateArtists(from: playcuts)
    }

    /// Consumes a stream of terminal metadata-enrichment transitions and
    /// re-donates each one via ``handleMetadataEnrichment(for:)``.
    ///
    /// Callers wire this to a live `PlaylistService` at app-launch time
    /// (`source.terminalMetadataTransitions()`); tests inject a
    /// ``MetadataEnrichmentTransitionsSource`` double. Runs until the
    /// underlying stream finishes.
    public func observeMetadataEnrichment(from source: MetadataEnrichmentTransitionsSource) async {
        for await playcut in source.terminalMetadataTransitions() {
            await handleMetadataEnrichment(for: playcut)
        }
    }

    /// Whether `playcut` was already sent to Spotlight by either donation
    /// path — the batch watermark has advanced past its `chronOrderID`, or
    /// it's the most recent per-tick current-playcut donation.
    private func wasPreviouslyDonated(_ playcut: Playcut) -> Bool {
        playcut.chronOrderID <= currentWatermark || playcut.id == lastDonatedCurrentPlaycut?.id
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
