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
//    the last-donated **id set** persisted in `DefaultsStorage`. Concerts
//    that dropped out of the window are evicted via
//    `ConcertSpotlightIndexer.deleteConcerts(withIdentifiers:)` — this is
//    what catches a cancellation *before* its date, which expiry alone would
//    miss (the show never happens, so its `expirationDate` is never
//    reached). Concerts newly present in the window are upserted at a
//    priority derived from `ForYouShelf`'s tiers.
//
//  Unlike the playcut service's high-water mark (a single `UInt64` that only
//  ever advances), the persisted state here is a **set of concert ids** that
//  can both grow and shrink between calls — the watermark idiom does not
//  transfer to a windowed, expiring index. Re-running `reconcile` with an
//  unchanged window is a no-op: nothing in `window`'s id set is new relative
//  to the persisted set, so neither `indexConcerts` nor `deleteConcerts` is
//  called.
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

    /// UserDefaults key for the persisted last-donated concert id set,
    /// JSON-encoded as a sorted `[Int]` (mirroring `DismissedConcertsStore`'s
    /// `Set<Int>` persistence idiom) rather than a single watermark scalar —
    /// concerts can leave this set as well as join it.
    public static let donatedIDsKey = "spotlight.concerts.donatedIDs"

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
    /// last-donated id set: evicts concerts that dropped out of the window,
    /// then upserts concerts newly present, at a priority derived from
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
    ///     Spotlight entirely. Defaults to empty.
    public func reconcile(
        window: [Concert],
        likedArtists: [LikedArtist] = [],
        stationCap: Int = 0,
        dismissedConcertIDs: Set<Int> = []
    ) async {
        let currentIDs = Set(window.map(\.id))
        var persisted = persistedIDs

        let departedIDs = persisted.subtracting(currentIDs)
        if !departedIDs.isEmpty {
            let identifiers = departedIDs.compactMap { ConcertID(concertID: $0)?.entityIdentifierString }
            do {
                try await indexer.deleteConcerts(withIdentifiers: identifiers)
                // Only drop the departed ids from the persisted set on a
                // successful delete — mirroring the batch playcut path's
                // "advance only on success" discipline, so a transient
                // Spotlight failure doesn't strand a departed concert as
                // "still indexed" when the next reconcile could retry it.
                persisted.subtract(departedIDs)
                persistedIDs = persisted
            } catch {
                Log(.warning, category: .general, "Concert Spotlight eviction failed for \(departedIDs.count) departed concert(s): \(error)")
            }
        }

        // Dedup: nothing in `window` is new relative to the (possibly just
        // updated) persisted set, so there is nothing left to upsert. This is
        // what makes re-running reconcile with an unchanged window a no-op.
        let newIDs = currentIDs.subtracting(persisted)
        guard !newIDs.isEmpty else { return }

        let tierByConcertID = Self.tierByConcertID(
            window: window,
            likedArtists: likedArtists,
            stationCap: stationCap,
            dismissedConcertIDs: dismissedConcertIDs
        )

        var donations: [ConcertDonation] = []
        var donatedIDs: [Int] = []
        for concert in window where newIDs.contains(concert.id) {
            guard let entity = ConcertEntity(concert: concert) else { continue }
            let priority = Self.priority(forTier: tierByConcertID[concert.id])
            let expirationDate = Self.endOfShowDay(concert.startsOn)
            donations.append(ConcertDonation(entity: entity, priority: priority, expirationDate: expirationDate))
            donatedIDs.append(concert.id)
        }

        guard !donations.isEmpty else { return }

        do {
            try await indexer.indexConcerts(donations)
            persisted.formUnion(donatedIDs)
            persistedIDs = persisted
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

    // MARK: - Persisted id set

    /// The last-donated concert id set, JSON-decoded from `donatedIDsKey`.
    /// Empty (rather than throwing) when the key is absent or the stored
    /// data doesn't decode — a fresh install and a pre-OT-F2 install both
    /// start from an empty set, which is safe: the first `reconcile` call
    /// simply treats every concert in the window as new.
    private var persistedIDs: Set<Int> {
        get {
            guard let data = storage.data(forKey: Self.donatedIDsKey),
                  let ids = try? JSONDecoder().decode([Int].self, from: data)
            else { return [] }
            return Set(ids)
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue.sorted()) else { return }
            storage.set(data, forKey: Self.donatedIDsKey)
        }
    }
}

#endif
