//
//  PlaycutHistoryStore.swift
//  Playlist
//
//  Persistent rolling history of playcuts observed from PlaylistService, day-bucketed
//  by broadcast date plus a durable rotation set, so Spotlight reindex handlers can
//  rebuild "the last 90 days plus every rotation track" without network I/O.
//
//  Created by Jake Bromberg on 07/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Foundation
import Logger

/// Persistent rolling history of playcuts, fed continuously from `PlaylistService.updates()`.
///
/// ## Storage layout
///
/// Backed by a dedicated `CacheCoordinator` (a `DiskCache` subdirectory under Application
/// Support in production):
/// - **Day buckets** — one `[Playcut]` entry per broadcast day, keyed by the day derived
///   from `Playcut.hour` in the station's time zone (not ingestion date). Each bucket is
///   deduped by playcut id with newest-snapshot-wins, so metadata enrichment re-broadcasts
///   refresh stored rows. Bucket lifespans are anchored to the broadcast day — a bucket
///   expires 90 days after broadcast no matter when it was last rewritten, and rows
///   broadcast outside the window are rejected at ingest. `CacheCoordinator`'s TTL
///   machinery prunes expired days for free (purge at init + lazy on read).
/// - **Rotation set** — a single entry holding every playcut seen with `rotation == true`,
///   written with a 365-day lifespan refreshed on every write and pruned of rows whose
///   broadcast is older than that window (at write time and again at read time), so the
///   set is bounded by age rather than accreting forever. Membership is sticky: a later
///   snapshot of a stored id refreshes its row even when the snapshot's own rotation flag
///   is false. The lifespan is deliberately finite: `CacheCoordinator` purges
///   `lifespan == .infinity` entries at init as legacy cleanup, so an infinite-lifespan
///   rotation set would be deleted on launch.
///
/// ## Write safety
///
/// Ingests are serialized: each read-merge-write chains onto the previous one, so the
/// subscription loop and `BackgroundRefreshController`'s direct call cannot interleave
/// and lose updates across the actor's suspension points. A read that fails on an
/// intact entry (``CacheCoordinator/Error/readFailed``) skips that key's write rather
/// than truncating it, and re-ingesting unchanged content performs no rewrite.
///
/// ## Reads
///
/// Reads are brute-force scans of the day buckets (newest-first) plus the rotation set —
/// no sidecar id-to-bucket index. The v1 backend mutates `hour` in place across
/// hourly-breakpoint moves, so ingest evicts each id from the adjacent day buckets;
/// when duplicates persist anyway (pre-existing data, non-adjacent moves), the snapshot
/// with the greater `timeCreated` wins at read. Reindex is a rare, system-initiated
/// event and the worst case (~90 buckets of small JSON) decodes in tens of milliseconds.
///
/// The store performs no network I/O and never clears storage wholesale; pruning is
/// TTL- and age-driven only.
public actor PlaycutHistoryStore {
    /// How long a day bucket remains readable after its broadcast day: the rolling
    /// history window.
    static let dayBucketLifespan: TimeInterval = 90 * 24 * 60 * 60

    /// How long the rotation set remains readable without a refreshing write, and how
    /// long an individual rotation row is retained after its broadcast.
    static let rotationLifespan: TimeInterval = 365 * 24 * 60 * 60

    /// Key prefix for day-bucket entries; the suffix is the broadcast date.
    private static let dayKeyPrefix = "day."

    /// Key for the single rotation-set entry.
    private static let rotationKey = "rotation-set"

    private let cacheCoordinator: CacheCoordinator
    private let clock: any Caching.Clock
    private var observationTask: Task<Void, Never>?

    /// The most recently enqueued ingest; each new ingest chains onto it.
    private var ingestTail: Task<Void, Never>?

    /// Creates a history store over the given cache coordinator.
    ///
    /// All writers must share a single instance — ingest serialization is
    /// per-instance, so two stores over the same storage could interleave
    /// read-merge-writes. Reads are safe from any instance.
    ///
    /// - Parameters:
    ///   - cacheCoordinator: Storage backend. Defaults to the dedicated
    ///     `playcut-history` disk cache. Tests inject a coordinator built over
    ///     `InMemoryCache` for isolation.
    ///   - clock: Time source for age-based pruning and lifespan anchoring. Must agree
    ///     with the coordinator's clock; defaults to the system clock. Tests inject the
    ///     same `MockClock` into both for deterministic TTL behavior.
    public init(
        cacheCoordinator: CacheCoordinator = .PlaycutHistory,
        clock: any Caching.Clock = SystemClock()
    ) {
        self.cacheCoordinator = cacheCoordinator
        self.clock = clock
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Ingestion

    /// Subscribes to the service's playlist broadcasts and ingests every update.
    ///
    /// `updates()` re-yields on every fresh fetch (and yields the cached playlist on
    /// subscribe when one is present), so foreground ticks and enrichment re-broadcasts
    /// accumulate here without extra wiring. Background refresh is the exception:
    /// `BackgroundRefreshController` calls ``ingest(_:)`` directly because its append
    /// must land inside the BGAppRefresh budget rather than race process suspension
    /// through this subscription.
    public func start(observing service: PlaylistService) {
        start(observing: service.updates())
    }

    /// Subscribes to an arbitrary playlist stream and ingests every update.
    ///
    /// Exposed separately from the `PlaylistService` overload so the subscription
    /// loop is unit-testable against an injected stream.
    public func start(observing updates: AsyncStream<Playlist>) {
        observationTask?.cancel()

        observationTask = Task { [weak self] in
            for await playlist in updates {
                guard !Task.isCancelled else { break }
                await self?.ingest(playlist.playcuts)
            }
        }
    }

    /// Persists a batch of playcuts into their day buckets and the rotation set.
    ///
    /// Buckets are keyed on broadcast date derived from `Playcut.hour`; rows broadcast
    /// outside the 90-day window are rejected so a stale re-broadcast cannot resurrect
    /// an expired bucket. Within each entry, rows are deduped by id with the incoming
    /// snapshot winning, so enrichment re-broadcasts keep history rows fresh. Rotation
    /// playcuts — and later snapshots of ids already in the rotation set — are upserted
    /// into the rotation set, refreshing its lifespan.
    ///
    /// Concurrent calls are serialized in arrival order; this method returns once its
    /// own batch has been persisted.
    public func ingest(_ playcuts: [Playcut]) async {
        guard !playcuts.isEmpty else { return }

        let previous = ingestTail
        let task = Task {
            await previous?.value
            await performIngest(playcuts)
        }
        ingestTail = task
        await task.value
    }

    /// How far in the future a row's broadcast may claim to be before it is
    /// rejected as corrupt rather than tolerated as clock skew.
    private static let futureTolerance: TimeInterval = 24 * 60 * 60

    /// The single serialized read-merge-write pass for one batch.
    private func performIngest(_ playcuts: [Playcut]) async {
        let now = Date(timeIntervalSinceReferenceDate: clock.now)

        // Same-batch duplicates (e.g. concatenated fetch windows) keep only the
        // freshest snapshot per id — otherwise the same id could land in two
        // buckets in one pass and Dictionary iteration order would decide which
        // one's adjacent-bucket eviction wins.
        let deduped = Dictionary(grouping: playcuts, by: \.id).values.compactMap { snapshots in
            snapshots.max { $0.timeCreated < $1.timeCreated }
        }

        // Day buckets: reject rows already outside the rolling window — an old
        // snapshot can't resurrect (and re-lease) an expired bucket — and rows
        // claiming a broadcast more than a day in the future (corrupt feed).
        let inWindow = deduped.filter { playcut in
            let age = now.timeIntervalSince(playcut.broadcastDate)
            return age < Self.dayBucketLifespan && age > -Self.futureTolerance
        }
        let buckets = Dictionary(grouping: inWindow, by: Self.dayKey(for:))
        for (key, incoming) in buckets {
            await upsert(key: key) { existing in
                let merged = Self.merge(incoming, into: existing)
                return (merged, Self.anchoredLifespan(for: merged, asOf: now))
            }

            // Evict these ids from the adjacent day buckets: the v1 backend moves
            // radioHour in place across hourly-breakpoint boundaries (±1 hour)
            // without touching timeCreated, so a move across midnight strands an
            // exact-tie stale copy in the neighboring bucket that no read-side
            // recency heuristic can rank against this one. If this upsert skips
            // on a failed read, the stale copy lingers — accepted (exact-tie
            // cases only, and rare; everything else the read backstop ranks).
            guard let representative = incoming.first else { continue }
            let incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
            for adjacentKey in Self.adjacentDayKeys(to: representative.broadcastDate) where adjacentKey != key {
                await upsert(key: adjacentKey) { existing in
                    let remaining = existing.filter { stored in
                        guard let incoming = incomingByID[stored.id] else { return true }
                        // Spare strictly newer stored snapshots: an out-of-order
                        // stale replay must not destroy the corrected copy. Ties
                        // still evict — that's the breakpoint-move case.
                        return stored.timeCreated > incoming.timeCreated
                    }
                    return (remaining, Self.anchoredLifespan(for: remaining, asOf: now))
                }
            }
        }

        // Rotation set: sticky membership — a later snapshot of a stored id updates
        // its row even when that snapshot's own rotation flag is false (corrections
        // can arrive on non-rotation re-broadcasts). Eligibility comes from the
        // PRE-dedup batch: an older rotation==true snapshot collapsed by a newer
        // rotation==false correction still inducts the id, exactly as the same two
        // snapshots would across two batches.
        let rotationEligibleIDs = Set(playcuts.filter(\.rotation).map(\.id))
        await upsert(key: Self.rotationKey) { existing in
            let memberIDs = Set(existing.map(\.id))
            let updates = deduped.filter { rotationEligibleIDs.contains($0.id) || memberIDs.contains($0.id) }
            let merged = Self.merge(updates, into: existing).filter { playcut in
                // Bound the set by age: drop rows broadcast more than a year ago
                // (and far-future rows, mirroring the day-bucket rejection).
                let age = now.timeIntervalSince(playcut.broadcastDate)
                return age < Self.rotationLifespan && age > -Self.futureTolerance
            }
            return (merged, Self.rotationLifespan)
        }
    }

    /// Lifespan for a day bucket anchored to its newest broadcast: however often
    /// the bucket is rewritten, it expires `dayBucketLifespan` after broadcast.
    /// Clamped to the window size so a tolerated near-future row can't extend it.
    private static func anchoredLifespan(for rows: [Playcut], asOf now: Date) -> TimeInterval {
        guard let newestBroadcast = rows.map(\.broadcastDate).max() else { return 0 }
        return min(dayBucketLifespan, dayBucketLifespan - now.timeIntervalSince(newestBroadcast))
    }

    /// Reads `key`, applies `transform` to the stored rows, and writes the result back.
    ///
    /// Skips the write when the read failed on an intact entry — writing a merge of
    /// "nothing" would truncate it — and when the transform leaves the content
    /// unchanged, so replayed batches don't rewrite (and re-timestamp) every entry.
    /// A transform that empties the entry removes it outright.
    private func upsert(
        key: String,
        transform: ([Playcut]) -> (rows: [Playcut], lifespan: TimeInterval)
    ) async {
        let existing: [Playcut]
        do {
            existing = try await cacheCoordinator.value(for: key)
        } catch CacheCoordinator.Error.noCachedResult {
            existing = []
        } catch is DecodingError {
            // The coordinator evicted the corrupt entry; start the key over.
            existing = []
        } catch {
            Log(.warning, category: .caching, "Skipping playcut-history write for \(key): read failed (\(error))")
            return
        }

        let (rows, lifespan) = transform(existing)
        guard rows != existing else { return }
        if rows.isEmpty {
            await cacheCoordinator.set(value: Optional<[Playcut]>.none, for: key, lifespan: 0)
        } else {
            // Defense in depth: the in-window filters should make a non-positive
            // lifespan unreachable, but never write an already-expired entry.
            guard lifespan > 0 else { return }
            await cacheCoordinator.set(value: rows, for: key, lifespan: lifespan)
        }
    }

    // MARK: - Reads

    /// Returns the stored playcuts matching the given ids.
    ///
    /// Ids not present in the store are omitted from the result — a miss is not an
    /// error. When multiple snapshots of an id are stored, the freshest wins (see
    /// ``allIndexable()``).
    public func playcuts(ids: Set<UInt64>) async -> [Playcut] {
        await allIndexable().filter { ids.contains($0.id) }
    }

    /// Returns every indexable playcut: the union of the last ~90 days of history and
    /// the rotation set, deduped by id.
    ///
    /// When the same id appears in multiple entries — the v1 backend mutates a
    /// playcut's `hour` in place across hourly-breakpoint moves, which can strand a
    /// stale copy in an adjacent day bucket — the snapshot with the greater
    /// `timeCreated` wins, with the newer bucket as the tiebreak.
    public func allIndexable() async -> [Playcut] {
        let now = Date(timeIntervalSinceReferenceDate: clock.now)
        var best: [UInt64: Playcut] = [:]

        // Buckets scan newest-first, so on a timeCreated tie the first-seen
        // (later-bucket) snapshot is kept.
        for bucket in await allBuckets() {
            for playcut in bucket {
                merge(playcut, into: &best)
            }
        }

        for playcut in await rotationSet(asOf: now) {
            merge(playcut, into: &best)
        }

        return best.values.sorted(by: >)
    }

    // MARK: - Private

    /// Keeps the fresher of the stored and candidate snapshots for an id.
    private func merge(_ playcut: Playcut, into best: inout [UInt64: Playcut]) {
        if let current = best[playcut.id] {
            guard playcut.timeCreated > current.timeCreated else { return }
        }
        best[playcut.id] = playcut
    }

    /// Cache key for the broadcast day containing the given playcut's hour.
    ///
    /// The day is resolved in the station's time zone, so a late-night play keys to the
    /// broadcast day listeners experienced rather than its UTC calendar date. The ISO
    /// date suffix sorts lexicographically in chronological order.
    static func dayKey(for playcut: Playcut) -> String {
        dayKey(forDate: playcut.broadcastDate)
    }

    private static func dayKey(forDate date: Date) -> String {
        let day = date.formatted(
            Date.ISO8601FormatStyle(timeZone: .wxycStation).year().month().day()
        )
        return dayKeyPrefix + day
    }

    /// Calendar in the station's time zone, for day arithmetic that respects DST.
    private static let stationCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        return calendar
    }()

    /// The day keys immediately before and after the given broadcast moment.
    ///
    /// ±1 day is sufficient for adjacent-bucket eviction: breakpoint moves shift
    /// `hour` by a single hour, so a moved play can only cross one midnight.
    private static func adjacentDayKeys(to date: Date) -> [String] {
        [-1, 1].compactMap { offset in
            stationCalendar.date(byAdding: .day, value: offset, to: date).map(dayKey(forDate:))
        }
    }

    /// Upserts incoming playcuts into an existing collection, deduped by id.
    ///
    /// The incoming snapshot wins unless the stored row has a strictly greater
    /// `timeCreated` — a stale out-of-order replay (e.g. the subscription
    /// re-broadcasting the cached playlist after a fresher direct ingest) must
    /// not overwrite the corrected copy. Ties overwrite: enrichments carry an
    /// unchanged `timeCreated` and must keep landing. The result is ordered
    /// newest-first by `chronOrderID`.
    private static func merge(_ incoming: [Playcut], into existing: [Playcut]) -> [Playcut] {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for playcut in incoming {
            if let stored = byID[playcut.id], stored.timeCreated > playcut.timeCreated {
                continue
            }
            byID[playcut.id] = playcut
        }
        return byID.values.sorted(by: >)
    }

    /// Decodes every live day bucket, newest-first. Expired buckets throw on read (and
    /// are lazily removed by the coordinator), so they simply drop out of the scan.
    /// Read failures on intact entries are logged — a reindex missing a day's rows
    /// should at least be visible — but don't fail the scan.
    private func allBuckets() async -> [[Playcut]] {
        let dayKeys = await cacheCoordinator.allEntries()
            .map(\.key)
            .filter { $0.hasPrefix(Self.dayKeyPrefix) }
            .sorted(by: >)

        var buckets: [[Playcut]] = []
        for key in dayKeys {
            do {
                let bucket: [Playcut] = try await cacheCoordinator.value(for: key)
                buckets.append(bucket)
            } catch CacheCoordinator.Error.readFailed {
                Log(.warning, category: .caching, "Skipping playcut-history bucket \(key) in read: read failed on intact entry")
            } catch {
                // Absent/expired (noCachedResult) or corrupt (already evicted and
                // reported by the coordinator) — drop out of the scan quietly.
            }
        }
        return buckets
    }

    /// Decodes the rotation set, retiring rows by broadcast age at read time.
    ///
    /// The write-time prune only runs when a new rotation play arrives; without
    /// this filter a row could be served up to ~2× the window after broadcast
    /// (365-day-old row inside a just-refreshed entry).
    private func rotationSet(asOf now: Date) async -> [Playcut] {
        do {
            let rows: [Playcut] = try await cacheCoordinator.value(for: Self.rotationKey)
            return rows.filter { playcut in
                let age = now.timeIntervalSince(playcut.broadcastDate)
                return age < Self.rotationLifespan && age > -Self.futureTolerance
            }
        } catch CacheCoordinator.Error.readFailed {
            Log(.warning, category: .caching, "Skipping playcut-history rotation set in read: read failed on intact entry")
            return []
        } catch {
            return []
        }
    }
}
