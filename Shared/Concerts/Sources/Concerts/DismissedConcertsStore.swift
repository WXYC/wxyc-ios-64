//
//  DismissedConcertsStore.swift
//  Concerts
//
//  The listener's "Not interested" set for the On Tour For You shelf: the concert
//  ids they've dismissed, so a dismissed show surfaces no card on any tier. Held
//  in memory as an observed `Set<Int>` and written through to a durable file on
//  every mutation, so a dismiss survives relaunch and repaints the shelf live.
//
//  Mirrors `LikedSongsStore`'s shape (synchronous load-at-init, atomic
//  write-through, errors logged not thrown) and its persistence rationale — user
//  curation, not a re-derivable cache, so it goes through the `FileStorage` seam
//  rather than the evicting Caching package. Concert ids churn out of the fetched
//  window within weeks, so the set stays small on its own.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger

/// The set of concert ids the listener has dismissed from the For You shelf.
///
/// `ids` is a stored, observed property (not a computed pass-through over the
/// file), so `@Observable` tracks it and the shelf re-renders the instant a card
/// is dismissed. Persistence is a write-through side effect layered on top.
@MainActor
@Observable
public final class DismissedConcertsStore {

    /// The dismissed concert ids. Read by the shelf to filter the window; mutated
    /// only through ``dismiss(_:)`` / ``resetState()`` so every change persists.
    public private(set) var ids: Set<Int> = []

    private let storage: FileStorage

    /// Creates a store, loading any previously-dismissed ids synchronously so the
    /// first shelf paint already reflects them. An unreadable file starts empty
    /// (logged, not fatal): losing dismissals degrades to showing a card again,
    /// never a crash.
    public init(storage: FileStorage) {
        self.storage = storage
        do {
            if let data = try storage.load() {
                ids = Set(try JSONDecoder().decode([Int].self, from: data))
            }
        } catch {
            Log(.warning, category: .caching, "Dismissed concerts store unreadable, starting empty: \(error)")
        }
    }

    /// Whether `id` has been dismissed.
    public func isDismissed(_ id: Int) -> Bool {
        ids.contains(id)
    }

    /// Records `id` as dismissed and persists. A no-op (no redundant write) when
    /// the id is already dismissed.
    public func dismiss(_ id: Int) {
        guard ids.insert(id).inserted else { return }
        persist()
    }

    /// Clears every dismissal and persists. A no-op when already empty. Backs the
    /// debug panel's "reset dismissed shows" affordance.
    public func resetState() {
        guard !ids.isEmpty else { return }
        ids.removeAll()
        persist()
    }

    /// Atomic write-through of the current set as a sorted id array (stable bytes
    /// for a set). A failed write is logged, not thrown — the in-memory set stays
    /// authoritative for the session.
    private func persist() {
        do {
            try storage.save(try JSONEncoder().encode(ids.sorted()))
        } catch {
            Log(.warning, category: .caching, "Dismissed concerts write-through failed: \(error)")
        }
    }
}
