//
//  ConcertSpotlightWindowObserver.swift
//  AppServices
//
//  The live caller (OT-C8, WXYC/wxyc-ios-64#654) that makes the concert
//  Spotlight pipeline non-dormant. OT-F2's
//  `ConcertSpotlightDonationService.reconcile(window:...)` and OT-F3's
//  `IndexedEntityQuery` reindex handlers both exist, but until this type
//  nothing in the running app ever fed the curated On Tour window into
//  `reconcile` — so no WXYC-artist show was ever donated to `wxyc.concerts`.
//  (The OT-F3 path only fires when the OS *requests* a reindex; it never
//  proactively populates the index.)
//
//  This is the concert analogue of the playcut side's
//  `Singletonia.startSpotlightDonation()` loop, which drives
//  `SpotlightDonationService.donateBatch(...)` on every playlist tick. Here the
//  driver is the On Tour window: `Singletonia` subscribes to
//  `Observations { onTourModel.allConcerts }` and hands each emitted window to
//  ``donate(window:reconciler:inputs:)``, which owns the two guards that keep
//  the app-lifecycle donation honest with the background-refresh budget:
//
//  * **Skip the empty window.** `OnTourModel.allConcerts` starts empty and stays
//    empty until the first load resolves, so an emitted empty window is the
//    "not loaded yet" sentinel — *not* "the curated window is genuinely empty."
//    Reconciling against it would read every previously-donated concert as
//    departed and evict the whole persisted index on every cold launch before
//    the load finishes. A genuinely-empty curated window (every show has
//    passed) needs no eviction anyway: each donated item already carries an
//    `expirationDate` pinned to the end of its show day, so Spotlight evicts it
//    on its own (see `ConcertSpotlightDonationService`'s expiry half).
//  * **Dedup on the window's id -> status signature.** `Observations` only
//    re-emits when `allConcerts` is reassigned, but a pull-to-refresh that
//    returns byte-identical data still reassigns it. Comparing the incoming
//    window's `(id, status)` signature to the last donated one collapses those
//    no-op refreshes to nothing, so a trivial repaint never burns an XPC
//    round-trip. The signature is `(id, status)` — not ids alone — so OT-C5's
//    status axis still gets through: a concert that stays in the window but
//    turns `soldOut`/`cancelled` changes the signature and re-reconciles.
//
//  Why this is safe alongside the OT-F3 reindex path (the "no double-donation"
//  acceptance criterion): both this observer and
//  `ConcertEntityQuery.reindex*Entities` upsert to the *same* identifier-keyed
//  `wxyc.concerts` `CSSearchableIndex`. `CSSearchableIndex` is keyed by
//  `uniqueIdentifier`, so donating a concert that's already indexed *replaces*
//  its item rather than adding a duplicate row — there is no way for the two
//  paths to produce two rows for one concert. They also share no mutable state:
//  the reindex path (`ConcertReindexer.donate`) is a wholesale upsert that
//  never touches this observer's persisted id -> status snapshot, and a
//  subsequent `reconcile` simply re-donates idempotently. See
//  `ConcertReindexer`'s doc comment for why the reindex path deliberately does
//  *not* route through `reconcile`.
//
//  Privacy: the loved-tier intersection (a listener's liked artists matched
//  against the window) happens entirely inside `reconcile`, on-device, against
//  the *local* `CSSearchableIndex`. No taste signal leaves the device — the
//  same invariant `ConcertSpotlightDonationService` documents.
//
//  Compiled out on watchOS and tvOS, matching
//  `ConcertSpotlightDonationService` — CoreSpotlight is unavailable there.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)

import Concerts
import Foundation

/// The reconcile entry point the observer drives, abstracted from the concrete
/// `ConcertSpotlightDonationService` so the observer can be exercised against a
/// recording spy in tests. `ConcertSpotlightDonationService` is the sole
/// production conformer.
public protocol ConcertSpotlightReconciling: Sendable {
    func reconcile(
        window: [Concert],
        likedArtists: [LikedArtist],
        stationCap: Int,
        dismissedConcertIDs: Set<Int>
    ) async
}

extension ConcertSpotlightDonationService: ConcertSpotlightReconciling {}

/// The on-device inputs a `reconcile` pass needs beyond the window itself —
/// gathered fresh at each donation so a like or a flag change since the last
/// window refresh is reflected. Mirrors the argument set
/// `OnTourTabView.forceConcertSpotlightReconcile()` already assembles for the
/// OT-Q2 debug trigger.
public struct ConcertSpotlightReconcileInputs: Sendable {
    /// The listener's id-bearing liked artists, matched on-device against the
    /// window for the loved tier.
    public let likedArtists: [LikedArtist]

    /// The station-recommended tier's cap (`ForYouShelf`'s `stationCap`).
    public let stationCap: Int

    /// Concerts the listener dismissed from the For You shelf — excluded from
    /// elevated tiers but still indexed at `defaultPriority`.
    public let dismissedConcertIDs: Set<Int>

    public init(
        likedArtists: [LikedArtist] = [],
        stationCap: Int = 0,
        dismissedConcertIDs: Set<Int> = []
    ) {
        self.likedArtists = likedArtists
        self.stationCap = stationCap
        self.dismissedConcertIDs = dismissedConcertIDs
    }
}

/// Feeds each fetched On Tour window into `reconcile`, skipping the
/// not-loaded-yet empty window and deduping byte-identical refreshes.
///
/// An `actor` so its `lastSignature` dedup state is race-free across the
/// main-actor `Observations` loop that drives it — `Singletonia` awaits
/// ``donate(window:reconciler:inputs:)`` per emitted window and the actor
/// serializes the reads/writes of that state.
public actor ConcertSpotlightWindowObserver {

    /// The id -> status signature of the window last handed to `reconcile`, or
    /// `nil` before the first donation. Compared against each incoming window to
    /// collapse no-op refreshes.
    private var lastSignature: [Int: ShowStatus]?

    public init() {}

    /// Donates `window` through `reconciler` unless it's the not-loaded-yet
    /// empty window, or its id -> status signature matches the last donated
    /// window.
    ///
    /// - Returns: `true` if `reconciler.reconcile` was called, `false` if the
    ///   window was skipped (empty or unchanged) — surfaced for tests; callers
    ///   can ignore it.
    @discardableResult
    public func donate(
        window: [Concert],
        reconciler: some ConcertSpotlightReconciling,
        inputs: ConcertSpotlightReconcileInputs
    ) async -> Bool {
        // The not-loaded-yet sentinel — never evict the whole persisted index
        // just because the window hasn't resolved. See the file-level comment.
        guard !window.isEmpty else { return false }

        let signature = Self.signature(of: window)
        guard signature != lastSignature else { return false }
        lastSignature = signature

        await reconciler.reconcile(
            window: window,
            likedArtists: inputs.likedArtists,
            stationCap: inputs.stationCap,
            dismissedConcertIDs: inputs.dismissedConcertIDs
        )
        return true
    }

    /// The window's id -> status signature — the dedup key. Duplicate ids in a
    /// window (never expected from the curated endpoint) resolve first-wins,
    /// matching `reconcile`'s own `statusByID` construction.
    private static func signature(of window: [Concert]) -> [Int: ShowStatus] {
        Dictionary(window.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
    }
}

#endif
