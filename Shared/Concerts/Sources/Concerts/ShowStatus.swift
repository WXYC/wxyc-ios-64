//
//  ShowStatus.swift
//  Concerts
//
//  Ticket-availability state for a concert. Raw values mirror Backend-Service's
//  `Concert.status` enum (`on_sale`/`sold_out`/`cancelled`/`rescheduled`) in
//  `wxyc-shared/api.yaml` v1.15.0.
//
//  Note on `free`: the backend `Concert` status enum does **not** include a
//  `free` value — that was a triangle-shows `EventStatus` case the old
//  `UpcomingShow` mirrored. It is retained here as a modeled status (the
//  presenter still renders a distinct "Free/RSVP" treatment for it) so no
//  presentation coverage is lost, and tolerant decode means a `free` wire value
//  would still map correctly if a future backend emits one. `rescheduled` is the
//  new wire value added to match the backend enum.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Ticket-availability state for a concert.
///
/// Decoding is tolerant: an unrecognized wire value degrades to ``unknown``
/// rather than throwing, so a future backend status never fails the enclosing
/// ``Concert`` decode. This mirrors the forward-compat idiom used across the
/// packages (`OnAir`, `metadataStatus`).
public enum ShowStatus: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Tickets are available for purchase.
    case onSale = "on_sale"

    /// The show has sold out. The venue page may still list holds/waitlists,
    /// so the CTA stays actionable — it just changes wording.
    case soldOut = "sold_out"

    /// The show was cancelled. No CTA emphasis; the ticket desaturates.
    case cancelled

    /// The show was rescheduled. Still actionable — the ticket link points at
    /// the (new) date's box office.
    case rescheduled

    /// A free show. The CTA becomes an RSVP/details link rather than a purchase.
    /// Not currently emitted by the backend `Concert` status enum (see the file
    /// header); retained as a modeled status.
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
    /// throwing. Raw synthesis would reject it and fail the whole ``Concert``
    /// decode over one cosmetic field.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ShowStatus(rawValue: raw) ?? .unknown
    }
}
