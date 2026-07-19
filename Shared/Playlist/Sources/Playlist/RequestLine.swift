//
//  RequestLine.swift
//  Playlist
//
//  Presence model for the studio's communication channels (requests and the
//  request line), derived from the tri-state OnAir signal. The say-hi
//  affordance on the on-air banner is a presence indicator: it appears only
//  for a named DJ. Confirmed automation closes the booth entirely — nobody
//  reads requests and nobody answers the phone — while an unreported state
//  leaves the booth open, since a human may be on the board.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Booth availability for listener communication, derived from ``OnAir``.
///
/// Drives three surfaces: the say-hi chip on the on-air banner (named DJ
/// only), the Request Line sheet, and the Station tab's "Talk to the booth"
/// rows (disabled under confirmed automation).
public struct RequestLine: Equatable, Sendable {
    /// The named DJ on the board, when the backend reports one.
    public let djName: String?

    /// Whether the booth can receive requests and calls.
    ///
    /// `true` when a human is — or may be — on the board; `false` only under
    /// confirmed automation, where a request would go unread and the phone
    /// would ring an empty room.
    public let boothIsOpen: Bool

    /// Whether the on-air banner should invite conversation (the say-hi chip).
    ///
    /// `true` only for a named DJ: the chip asserts presence, so it never
    /// appears on a guess.
    public var invitesConversation: Bool { djName != nil }

    public init(onAir: OnAir) {
        switch onAir {
        case .dj(let name):
            djName = name
            boothIsOpen = true
        case .automation:
            djName = nil
            boothIsOpen = false
        case .unknown:
            djName = nil
            boothIsOpen = true
        }
    }
}
