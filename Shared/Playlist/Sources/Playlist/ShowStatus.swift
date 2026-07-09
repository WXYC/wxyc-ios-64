//
//  ShowStatus.swift
//  Playlist
//
//  Ticket-availability state for a touring-band show surfaced on a playcut.
//  Raw values mirror triangle-shows' `EventStatus` Postgres enum exactly
//  (on_sale/sold_out/cancelled/free); see WXYC/triangle-shows backend/app/models.py.
//
//  Lives in the `Playlist` package alongside `Playcut` because an upcoming show
//  is an enrichment carried on a played track — the same role `artistBio` and
//  the streaming links already play — not a standalone browse domain. If the
//  separate "Touring Soon" tab (triangle-shows-integration-proposal.md) is built,
//  this can be promoted to a shared `Concerts` package.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Ticket-availability state for an upcoming show.
///
/// Decoding is tolerant: an unrecognized wire value degrades to ``unknown``
/// rather than throwing, so a future backend status never fails the enclosing
/// ``UpcomingShow`` decode. This mirrors the forward-compat idiom used across
/// the package (`OnAir`, `metadataStatus`).
public enum ShowStatus: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Tickets are available for purchase.
    case onSale = "on_sale"

    /// The show has sold out. The venue page may still list holds/waitlists,
    /// so the CTA stays actionable — it just changes wording.
    case soldOut = "sold_out"

    /// The show was cancelled. No CTA emphasis; the ticket desaturates.
    case cancelled

    /// A free show. The CTA becomes an RSVP/details link rather than a purchase.
    case free

    /// An unrecognized or absent status. Rendered neutrally (like ``onSale``
    /// without a special pill), never hidden.
    case unknown

    /// Builds a status from a raw wire string, mapping unrecognized or `nil`
    /// values to ``unknown``.
    public init(wire: String?) {
        self = wire.flatMap(ShowStatus.init(rawValue:)) ?? .unknown
    }

    /// Tolerant decode: an unknown raw string becomes ``unknown`` instead of
    /// throwing. Raw synthesis would reject it and fail the whole
    /// ``UpcomingShow`` decode over one cosmetic field.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ShowStatus(rawValue: raw) ?? .unknown
    }
}
