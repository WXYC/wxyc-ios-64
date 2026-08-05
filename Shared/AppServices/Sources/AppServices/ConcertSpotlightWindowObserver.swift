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
//  ``donate(window:reconciler:inputs:)``, whose sole job is the one guard the
//  reconcile service cannot make on its own — distinguishing the not-loaded-yet
//  empty window from a genuine one:
//
//  * **Skip the empty window until the first real load.**
//    `OnTourModel.allConcerts` starts empty and stays empty until the first
//    load resolves, so an empty window emitted *before any non-empty window has
//    been donated* is the "not loaded yet" sentinel — *not* "the curated window
//    is genuinely empty." Reconciling against it would read every
//    previously-donated concert as departed and evict the whole persisted index
//    on every cold launch before the load finishes. Once a real (non-empty)
//    window has been donated, a later empty window is a genuine shrink-to-zero —
//    a successful fetch that returned no shows — and *is* forwarded, so
//    `reconcile` evicts the departed shows. (Expiry alone would miss a
//    cancelled-then-departed show, whose `expirationDate` is still in the
//    future; see `ConcertSpotlightDonationService`'s eviction half.) The gate is
//    ``hasDonated``.
//
//  Deduping unchanged windows is deliberately *not* this observer's job — it is
//  `reconcile`'s. `reconcile` diffs each window against its persisted
//  id -> status snapshot and short-circuits (no CoreSpotlight call) when nothing
//  changed, so a byte-identical pull-to-refresh already collapses to a no-op
//  there. Crucially, `reconcile` advances that snapshot *only on a successful
//  index write*, so a transient CoreSpotlight failure is retried on the next
//  pass. An earlier design mirrored the snapshot here as a separate dedup
//  signature; that second copy could drift ahead of `reconcile`'s on a failed
//  write and suppress the very retry the snapshot discipline exists to allow, so
//  the observer now keeps no window state beyond the ``hasDonated`` sentinel.
//
//  Why this is safe alongside the OT-F3 reindex path (the "no double-donation"
//  acceptance criterion): both this observer and
//  `ConcertEntityQuery.reindex*Entities` upsert to the *same* identifier-keyed
//  `wxyc.concerts` `CSSearchableIndex`. `CSSearchableIndex` is keyed by
//  `uniqueIdentifier`, so donating a concert that's already indexed *replaces*
//  its item rather than adding a duplicate row — there is no way for the two
//  paths to produce two rows for one concert. They also share no mutable state:
//  the reindex path (`SpotlightReindexer<Concert>.donate`) is a wholesale
//  upsert that never touches this observer's persisted id -> status snapshot,
//  and a subsequent `reconcile` simply re-donates idempotently. See
//  `SpotlightReindexer`'s doc comment for why the reindex path deliberately
//  does *not* route through `reconcile`.
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
/// gathered fresh at each donation. Assembled once by
/// `Singletonia.currentConcertSpotlightInputs`, the single source both this
/// live loop and `OnTourTabView`'s OT-Q2 debug trigger read.
///
/// Note the granularity: because `reconcile` re-donates a concert only when its
/// identity or `status` changes, an inputs-only change (a new like, a dismissal,
/// a station-cap flag flip) against an otherwise-unchanged window does not
/// re-tier that concert in Spotlight immediately — it takes effect the next time
/// the window's membership or a status changes and the concert is re-donated.
/// Fresh inputs at each donation is what makes that eventual re-tier correct; it
/// is not a promise of instantaneous reflection.
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

/// Feeds each fetched On Tour window into `reconcile`, skipping only the
/// not-loaded-yet empty window (dedup of unchanged windows is `reconcile`'s
/// own responsibility — see the file-level comment).
///
/// An `actor` so its ``hasDonated`` gate is race-free across the main-actor
/// `Observations` loop that drives it — `Singletonia` awaits
/// ``donate(window:reconciler:inputs:)`` per emitted window and the actor
/// serializes the reads/writes of that state.
public actor ConcertSpotlightWindowObserver {

    /// Whether a non-empty window has been forwarded to `reconcile` yet. Until
    /// it has, an empty window is the "not loaded yet" sentinel and is skipped;
    /// afterward, an empty window is a genuine shrink-to-zero and is forwarded so
    /// `reconcile` evicts the departed shows.
    private var hasDonated = false

    public init() {}

    /// Forwards `window` to `reconciler`, skipping only the not-loaded-yet empty
    /// window (an empty window seen before any non-empty window has been
    /// donated). Everything else — including a genuine shrink-to-zero and a
    /// byte-identical refresh — is forwarded; `reconcile` diffs against its
    /// persisted snapshot and no-ops when nothing changed.
    ///
    /// - Returns: `true` if `reconciler.reconcile` was called, `false` if the
    ///   not-loaded-yet empty window was skipped — surfaced for tests; callers
    ///   can ignore it.
    @discardableResult
    public func donate(
        window: [Concert],
        reconciler: some ConcertSpotlightReconciling,
        inputs: ConcertSpotlightReconcileInputs
    ) async -> Bool {
        // The not-loaded-yet sentinel: an empty window before any real load has
        // resolved. Never reconcile against it — reconcile would read every
        // previously-donated concert as departed and evict the whole persisted
        // index on cold launch. Once a non-empty window has been donated, a
        // later empty window is a genuine shrink-to-zero and IS forwarded so the
        // departed shows are evicted. See the file-level comment.
        guard hasDonated || !window.isEmpty else { return false }
        hasDonated = true

        await reconciler.reconcile(
            window: window,
            likedArtists: inputs.likedArtists,
            stationCap: inputs.stationCap,
            dismissedConcertIDs: inputs.dismissedConcertIDs
        )
        return true
    }
}

#endif
