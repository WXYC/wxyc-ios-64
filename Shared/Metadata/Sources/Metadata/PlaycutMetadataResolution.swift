//
//  PlaycutMetadataResolution.swift
//  Metadata
//
//  Accumulates the playcut detail card's metadata from its two independent
//  sources — the resolve on appear and the enrichment repair — so that neither
//  the order they land in nor a failure of one can degrade the card.
//
//  Created by Jake Bromberg on 08/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The detail card's rendered metadata, accumulated from two sources that
/// complete independently and in either order.
///
/// The card has two producers: the resolve that runs on appear (which may take
/// a proxy round-trip, and on a bad connection can take minutes), and the
/// repair that fires when the row's server-side enrichment lands (#812). Left
/// to overwrite each other, a slow initial resolve returning *after* a repair
/// would restore the pre-enrichment snapshot permanently — the original bug,
/// reintroduced under exactly the network conditions that motivated it.
///
/// Storing both and deriving ``metadata`` removes the question: arrival order
/// cannot matter, because the rendered value is a pure function of the two
/// slots rather than of the sequence of writes. Where both sources speak to a
/// field, the repair wins — it comes from the row Backend has finished
/// enriching, which outranks whatever the proxy fuzzy-matched mid-flight.
/// Where only one speaks, that one is used, so neither source can ever remove
/// information the other contributed.
public struct PlaycutMetadataResolution: Sendable, Equatable {
    /// What the on-appear resolve produced, once it has.
    public private(set) var initial: PlaycutMetadata?

    /// What the enrichment repair produced, once it has. Outranks ``initial``.
    public private(set) var repaired: PlaycutMetadata?

    /// The value to render: the two slots coalesced, repair preferred.
    ///
    /// Stored rather than computed because the card reads it many times per
    /// render pass — once each for the metadata section's content gate and its
    /// argument, the reviews gate and its argument, the streaming gate and its
    /// argument, the external-links gate, and again from the artwork loader.
    /// It only changes on ``recordInitial(_:)``/``recordRepair(_:)``, so
    /// recomputing the three-record coalesce on every read buys nothing. Kept
    /// consistent by ``recompute()``, the single writer both mutators call.
    public private(set) var metadata: PlaycutMetadata = .empty

    public init() {}

    /// Whether neither source has reported yet — the card's loading state.
    public var isLoading: Bool {
        initial == nil && repaired == nil
    }

    /// Whether the streaming section should still read as "working on it"
    /// rather than as "this record isn't on these services".
    ///
    /// ``isLoading`` alone is the wrong predicate for that section, because it
    /// only asks whether *either* producer has reported. The on-appear resolve
    /// of a row Backend is still enriching reports promptly and reports
    /// nothing: the proxy answers a `pending` row with its base columns and no
    /// streaming URLs. `isLoading` flips false, and all five tiles drop to the
    /// same 0.3-opacity treatment they use for a service that genuinely has no
    /// link — while the ``recordRepair(_:)`` that will fill them is still in
    /// flight. The two states are visually identical and mean opposite things.
    ///
    /// - Parameter canBeRepaired: `PlaycutMetadataResolver.shouldObserveEnrichment(for:)`
    ///   for the card's playcut — whether a repair can still arrive at all.
    ///   Passed in rather than derived because this type deliberately knows
    ///   nothing about the row it was accumulated for.
    ///
    /// A repair landing is what ends the pending state, not the row's status
    /// going terminal. `canBeRepaired` is computed from the playcut snapshot
    /// captured at row-tap time, and nothing writes back to that snapshot (see
    /// `PlaycutDetailView`'s repair task), so it stays `true` for the life of
    /// the card. Keying on ``repaired`` instead means a row that enriches to a
    /// genuine no-match settles into the empty state exactly once Backend has
    /// said so, rather than spinning forever.
    public func isStreamingPending(canBeRepaired: Bool) -> Bool {
        if isLoading { return true }
        guard repaired == nil, canBeRepaired else { return false }
        return !metadata.streaming.hasAny
    }

    /// Records the on-appear resolve. Safe to call after a repair has landed;
    /// it fills gaps rather than overwriting.
    public mutating func recordInitial(_ metadata: PlaycutMetadata) {
        initial = metadata
        recompute()
    }

    /// Records an enrichment repair.
    public mutating func recordRepair(_ metadata: PlaycutMetadata) {
        repaired = metadata
        recompute()
    }

    private mutating func recompute() {
        metadata = switch (repaired, initial) {
        case let (repaired?, initial?):
            repaired.coalescing(over: initial)
        case let (repaired?, nil):
            repaired
        case let (nil, initial?):
            initial
        case (nil, nil):
            .empty
        }
    }
}
