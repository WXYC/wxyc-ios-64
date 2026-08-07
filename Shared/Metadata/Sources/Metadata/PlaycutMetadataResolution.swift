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

    public init() {}

    /// The value to render: the two slots coalesced, repair preferred.
    public var metadata: PlaycutMetadata {
        switch (repaired, initial) {
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

    /// Whether neither source has reported yet — the card's loading state.
    public var isLoading: Bool {
        initial == nil && repaired == nil
    }

    /// Records the on-appear resolve. Safe to call after a repair has landed;
    /// it fills gaps rather than overwriting.
    public mutating func recordInitial(_ metadata: PlaycutMetadata) {
        initial = metadata
    }

    /// Records an enrichment repair.
    public mutating func recordRepair(_ metadata: PlaycutMetadata) {
        repaired = metadata
    }
}
