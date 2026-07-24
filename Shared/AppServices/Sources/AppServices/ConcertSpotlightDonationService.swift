//
//  ConcertSpotlightDonationService.swift
//  AppServices
//
//  Feeds the `wxyc.concerts` Spotlight index with **reconcile + expiry**
//  semantics — the OT-F2 crux (`docs/ideas/spotlight-on-tour-entities.md`).
//  This is deliberately NOT a watermark service like `SpotlightDonationService`:
//  a playcut is a permanently-true historical fact, so the playlist index only
//  ever grows. A concert is a future event that stops being true the moment it
//  happens or is cancelled, so the concert index must shrink too. Two
//  mechanisms work together:
//
//  * **Expiry** — every donated concert's Spotlight item carries an
//    `expirationDate` pinned to the end of its calendar day in the station
//    (US Eastern) zone, computed by `endOfShowDay(_:)`. Spotlight evicts the
//    item automatically once that instant passes — no polling, no cleanup
//    task. This is the primary defense against a stale "this show already
//    happened" result.
//  * **Reconcile** — `reconcile(window:likedArtists:stationCap:dismissedConcertIDs:)`
//    diffs the caller's fetched concert window (`OnTourModel.allConcerts`,
//    the whole curated On Tour window, already bounded to ~100 rows) against
//    the last-donated **id -> status snapshot** persisted in
//    `DefaultsStorage` (see the OT-C5 paragraph below for the status half).
//    Concerts that dropped out of the window, or that are still in the
//    window but turned `cancelled`, are evicted via
//    `ConcertSpotlightIndexer.deleteConcerts(withIdentifiers:)` — this is
//    what catches a cancellation *before* its date, which expiry alone would
//    miss (the show never happens, so its `expirationDate` is never
//    reached). Concerts newly present in the window, or still present with a
//    changed non-cancelled status, are upserted at a priority derived from
//    `ForYouShelf`'s tiers.
//
//  Unlike the playcut service's high-water mark (a single `UInt64` that only
//  ever advances), the persisted state here is an **id -> `ShowStatus`
//  snapshot map** that can both grow and shrink between calls — the
//  watermark idiom does not transfer to a windowed, expiring index.
//  Re-running `reconcile` with an unchanged window (same ids, same statuses)
//  is a no-op: nothing in `window` is new or changed relative to the
//  persisted snapshot, so neither `indexConcerts` nor `deleteConcerts` is
//  called.
//
//  OT-C5 adds the **status axis**: OT-F2's original persisted state was a
//  bare `Set<Int>` of donated ids, which can only see a concert joining or
//  leaving the window — it's blind to a status change on a concert that
//  stays in the window the whole time (`onSale` -> `soldOut`, a rescheduled
//  date, etc.). Upgrading the persisted set to an id -> `ShowStatus` map
//  lets `reconcile` diff on status too: a still-in-window concert whose
//  status differs from its snapshot is either re-donated (idempotent
//  `indexConcerts` upsert, refreshed attribute set + a fresh
//  `expirationDate`) or evicted, depending on the new status.
//  `cancelled` evicts via the same `deleteConcerts` path as a departed
//  concert — a cancelled show is gone even though it's still in the window
//  and its `expirationDate` (pinned to the show's own date) hasn't been
//  reached yet. Every other status (`onSale`/`soldOut`/`rescheduled`/`free`/
//  `unknown`) re-donates instead of evicting: a sold-out or rescheduled show
//  is still real, findable information, so only `cancelled` and leaving the
//  window remove a row. An unchanged status is a no-op, same as an unchanged
//  identity. See the "Planning-review decisions" comment on
//  WXYC/wxyc-ios-64#628 for the full rationale.
//
//  Priority tiers (`lovedPriority` > `stationRecommendedPriority` >
//  `defaultPriority`) mirror `ForYouShelf.recommendations(_:)`'s own
//  ordering: a concert whose headliner is a liked artist ranks above one the
//  station recommends, which ranks above everything else in the window.
//  `defaultPriority` is deliberately below `stationRecommendedPriority` (and
//  `SpotlightDonationService.batchPriority`, which it matches) rather than
//  reusing it, so the "rest" tier never crowds out a genuinely-recommended
//  concert or playcut in a mixed Spotlight ranking.
//
//  Privacy: `CSSearchableIndex` is local to the device. Donating a
//  listener's `loved` concerts (matched on-device against their likes) to
//  the *local* index leaks no taste signal — nothing here ever reaches the
//  network. See the design doc's "Privacy — donation stays on-device" section.
//
//  This file is compiled out on watchOS and tvOS, matching
//  `SpotlightDonationService` — see AppServices/Package.swift for the
//  platform-gated `WXYCIntents` dependency.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)

import Caching
import Concerts
import Foundation
import Logger
import WXYCIntents

public actor ConcertSpotlightDonationService: Sendable {

    // MARK: - Constants

    /// UserDefaults key for the persisted last-donated concert snapshot, an
    /// id -> `ShowStatus` map JSON-encoded via `Dictionary`'s `Int`-keyed
    /// special case (mirroring `DismissedConcertsStore`'s `Set<Int>`
    /// persistence idiom for the id half) rather than a single watermark
    /// scalar — concerts can leave this map as well as join it, and OT-C5
    /// needs the status half to detect a transition on a concert that never
    /// left the window.
    ///
    /// OT-C5 renames this from the OT-F2-era `donatedIDsKey` rather than
    /// reusing the key with a new payload shape. No migration is needed —
    /// nothing is persisted in production yet (see the "Planning-review
    /// decisions" comment on WXYC/wxyc-ios-64#628) — and a distinct key
    /// means a stale pre-OT-C5 `[Int]` payload under the old key is simply
    /// orphaned rather than mis-decoded.
    public static let donatedSnapshotKey = "spotlight.concerts.donatedSnapshot"

    /// Priority for a concert whose headliner is a liked artist
    /// (`ForYouRecommendation.Tier.loved`). Matches
    /// `SpotlightDonationService.currentPlaycutPriority`'s elevated tier.
    public static let lovedPriority = 500

    /// Priority for a concert the station itself recommends
    /// (`ForYouRecommendation.Tier.stationRecommended`), with no personal
    /// tie. Matches `SpotlightDonationService.batchPriority`'s normal tier.
    public static let stationRecommendedPriority = 100

    /// Priority for every other concert in the window — still indexed (so
    /// it's findable) but ranked below both personalized tiers. Deliberately
    /// below `stationRecommendedPriority`.
    public static let defaultPriority = 50

    // MARK: - Dependencies

    private let storage: DefaultsStorage
    private let indexer: ConcertSpotlightIndexer

    // MARK: - Init

    public init(storage: DefaultsStorage, indexer: ConcertSpotlightIndexer) {
        self.storage = storage
        self.indexer = indexer
    }

    // MARK: - Public API

    /// Reconciles the fetched concert `window` against the persisted
    /// last-donated id -> status snapshot: evicts concerts that dropped out
    /// of the window *or* transitioned to `cancelled` while still in it,
    /// then upserts concerts that are newly present or whose status changed
    /// (to anything other than `cancelled`), at a priority derived from
    /// `ForYouShelf`'s tiers.
    ///
    /// - Parameters:
    ///   - window: The full fetched curated window (`OnTourModel.allConcerts`).
    ///     Already bounded to the On Tour page size (~100 rows), so one
    ///     reconcile pass never exceeds the background-refresh budget.
    ///   - likedArtists: The listener's id-bearing liked artists, matched
    ///     on-device against `window` — see `ForYouShelf`. Defaults to empty
    ///     (no loved tier; every concert falls through to station/default).
    ///   - stationCap: The station-recommended tier's cap. Defaults to `0`
    ///     (tier off), matching `ForYouShelf.recommendations(_:)`'s own
    ///     default.
    ///   - dismissedConcertIDs: Concerts the listener dismissed from the For
    ///     You shelf — excluded from tier consideration (so a dismissed
    ///     concert never donates at an elevated priority) but still indexed
    ///     at `defaultPriority` when present in `window`, since dismissal is
    ///     a personalization signal, not a request to hide the show from
    ///     Spotlight entirely. Dismissal never evicts or blocks a status
    ///     re-donation — orthogonal to the status axis below. Defaults to
    ///     empty.
    public func reconcile(
        window: [Concert],
        likedArtists: [LikedArtist] = [],
        stationCap: Int = 0,
        dismissedConcertIDs: Set<Int> = []
    ) async {
        let statusByID = Dictionary(window.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        let currentIDs = Set(statusByID.keys)
        let snapshot = persistedSnapshot
        var persisted = snapshot

        let previousIDs = Set(snapshot.keys)
        let departedIDs = previousIDs.subtracting(currentIDs)
        let stillPresentIDs = previousIDs.intersection(currentIDs)

        // A still-in-window concert that turned `cancelled` is gone even
        // though it hasn't reached its `expirationDate` yet — evict it the
        // same way a departed concert is evicted, rather than re-donating a
        // dead show.
        let cancelledIDs = stillPresentIDs.filter { statusByID[$0] == .cancelled }

        let evictIDs = departedIDs.union(cancelledIDs)
        if !evictIDs.isEmpty {
            let identifiers = evictIDs.compactMap { ConcertID(concertID: $0)?.entityIdentifierString }
            do {
                try await indexer.deleteConcerts(withIdentifiers: identifiers)
                // Only drop the evicted ids from the persisted snapshot on a
                // successful delete — mirroring the batch playcut path's
                // "advance only on success" discipline, so a transient
                // Spotlight failure doesn't strand a departed or cancelled
                // concert as "still indexed" when the next reconcile could
                // retry it.
                persisted = persisted.filter { !evictIDs.contains($0.key) }
                persistedSnapshot = persisted
            } catch {
                Log(.warning, category: .general, "Concert Spotlight eviction failed for \(evictIDs.count) departed/cancelled concert(s): \(error)")
            }
        }

        // Concerts to (re-)donate: newly present in the window, or still
        // present with a status that differs from its last-donated snapshot
        // (excluding `cancelled`, which is handled by eviction above, not
        // re-donation). This dedup — nothing left once identity and status
        // both match the snapshot — is what makes re-running reconcile with
        // an unchanged window a no-op.
        let newIDs = currentIDs.subtracting(previousIDs)
        let changedIDs = stillPresentIDs.subtracting(cancelledIDs).filter { statusByID[$0] != snapshot[$0] }
        let donateIDs = newIDs.union(changedIDs)
        guard !donateIDs.isEmpty else { return }

        let tierByConcertID = Self.tierByConcertID(
            window: window,
            likedArtists: likedArtists,
            stationCap: stationCap,
            dismissedConcertIDs: dismissedConcertIDs
        )

        var donations: [ConcertDonation] = []
        var donatedStatusByID: [Int: ShowStatus] = [:]
        for concert in window where donateIDs.contains(concert.id) {
            guard let entity = ConcertEntity(concert: concert) else { continue }
            let priority = Self.priority(forTier: tierByConcertID[concert.id])
            let expirationDate = Self.endOfShowDay(concert.startsOn)
            donations.append(ConcertDonation(entity: entity, priority: priority, expirationDate: expirationDate))
            donatedStatusByID[concert.id] = concert.status
        }

        guard !donations.isEmpty else { return }

        do {
            try await indexer.indexConcerts(donations)
            // Only advance the persisted snapshot's status for ids that were
            // actually indexed successfully — same "advance only on
            // success" discipline as eviction above, so a failed re-donation
            // is retried (not silently treated as caught up) next reconcile.
            for (id, status) in donatedStatusByID {
                persisted[id] = status
            }
            persistedSnapshot = persisted
        } catch {
            Log(.warning, category: .general, "Concert Spotlight donation failed for \(donations.count) concert(s): \(error)")
        }
    }

    // MARK: - Priority tiers

    /// Maps each concert id in `window` to the `ForYouShelf` tier it
    /// qualifies for, or omits it when it qualifies for neither — the
    /// "rest" tier is the absence of a dictionary entry, not a case.
    private static func tierByConcertID(
        window: [Concert],
        likedArtists: [LikedArtist],
        stationCap: Int,
        dismissedConcertIDs: Set<Int>
    ) -> [Int: ForYouRecommendation.Tier] {
        let recommendations = ForYouShelf.recommendations(
            concerts: window,
            likedArtists: likedArtists,
            stationCap: stationCap,
            dismissedConcertIDs: dismissedConcertIDs
        )
        return Dictionary(recommendations.map { ($0.concert.id, $0.tier) }, uniquingKeysWith: { first, _ in first })
    }

    private static func priority(forTier tier: ForYouRecommendation.Tier?) -> Int {
        switch tier {
        case .loved: return lovedPriority
        case .stationRecommended: return stationRecommendedPriority
        case nil: return defaultPriority
        }
    }

    // MARK: - Expiry

    /// The station-zone (US Eastern) end of `startsOn`'s calendar day — the
    /// start of the *next* day, so a donated concert's Spotlight item stays
    /// valid through the entirety of its show day and expires the moment
    /// that day ends. Falls back to `startsOn` itself if `dateInterval(of:for:)`
    /// can't resolve an interval (unreachable for a Gregorian calendar, but
    /// keeps this force-unwrap-free).
    static func endOfShowDay(_ startsOn: Date) -> Date {
        stationCalendar.dateInterval(of: .day, for: startsOn)?.end ?? startsOn
    }

    /// The station's broadcast time zone (US Eastern), duplicated locally
    /// because `Concerts`' `TimeZone.wxycStation` is internal to that
    /// module — the same duplication idiom `ConcertsTesting`'s
    /// `ConcertStubs.swift` already uses for the identical reason, rather
    /// than widening `Concerts`' public API for one call site.
    private static let stationTimeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    private static let stationCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stationTimeZone
        return calendar
    }()

    // MARK: - Persisted id -> status snapshot

    /// The last-donated concert snapshot, JSON-decoded from
    /// `donatedSnapshotKey` as an id -> `ShowStatus` map. Empty (rather than
    /// throwing) when the key is absent or the stored data doesn't decode —
    /// a fresh install and a pre-OT-C5 install (whose stored payload, if
    /// any, was written under the old `donatedIDsKey` and so is never read
    /// here) both start from an empty map, which is safe: the first
    /// `reconcile` call simply treats every concert in the window as new.
    private var persistedSnapshot: [Int: ShowStatus] {
        get {
            guard let data = storage.data(forKey: Self.donatedSnapshotKey),
                  let snapshot = try? JSONDecoder().decode([Int: ShowStatus].self, from: data)
            else { return [:] }
            return snapshot
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            storage.set(data, forKey: Self.donatedSnapshotKey)
        }
    }
}

#endif
