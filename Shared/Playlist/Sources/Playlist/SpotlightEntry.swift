//
//  SpotlightEntry.swift
//  Playlist
//
//  A who's-on row from the flowsheet: the person or group in the spotlight of the open show.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A spotlight row: from this row on, the named person or group is the focus of the show, until
/// the next spotlight row or the end of the show. A `host` row hands the focus back.
///
/// The role stays the raw `spotlight_role` string, not an enum, so an unrecognized future role
/// survives the decode and renders with a neutral label (see ``roleLine``).
public struct SpotlightEntry: PlaylistEntry {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
    public let timeCreated: UInt64
    /// The show the row was logged in. A spotlight only leads while it belongs to the open show.
    public let showID: UInt64?
    public let role: String
    public let name: String

    public init(id: UInt64, hour: UInt64, chronOrderID: UInt64, timeCreated: UInt64, showID: UInt64?, role: String, name: String) {
        self.id = id
        self.hour = hour
        self.chronOrderID = chronOrderID
        self.timeCreated = timeCreated
        self.showID = showID
        self.role = role
        self.name = name
    }

    /// Whether the row hands the focus back to the host instead of naming someone.
    public var isHost: Bool { role == "host" }

    /// The role's label without the name, or `nil` for a `host` row; medium and large widgets show
    /// it on its own line. An unknown role gets the neutral "On air".
    public var roleLabel: String? { roleCopy.label }

    /// What Siri says the person is doing ("in the studio"), or `nil` for a `host` row and for an
    /// unknown role, which is spoken with neutral wording.
    public var spokenActivity: String? { roleCopy.activity }

    /// The one table of role copy: the on-screen label and the spoken activity for each raw role.
    private var roleCopy: (label: String?, activity: String?) {
        switch role {
        case "guest": ("In the studio", "in the studio")
        case "performer": ("Live in the studio", "playing live in the studio")
        case "reader": ("Reading now", "reading")
        case "dj": ("Now mixing", "mixing")
        case "host": (nil, nil)
        default: ("On air", nil)
        }
    }

    /// The line every surface shows for this entry, or `nil` for a `host` row: the label, then the name.
    public var roleLine: String? { roleLabel.map { "\($0): \(name)" } }
}

public extension Playlist {
    /// The open show's current who's-on entry, led or not: the show's `spotlight` when it belongs to
    /// the open show (which must have an id) and is not a `host` row. The one same-show check, shared
    /// with ``nowPlayingLead``; the widget's guest line under a leading song reads it.
    var openShowSpotlight: SpotlightEntry? {
        guard case .dj(_, let show?) = onAir, let showID = show.id,
              let spotlight = show.spotlight, spotlight.showID == showID, !spotlight.isHost else { return nil }
        return spotlight
    }

    /// The "now" line for the open show: the current who's-on entry's role line, or `nil` when
    /// there is no entry, it is a `host` row, or it belongs to another show. Shown on every show,
    /// under the DJ on a freeform one and in the program card on a specialty one.
    var nowLine: String? {
        guard case .dj(_, let show?) = onAir, let spotlight = show.spotlight,
              show.id == nil || spotlight.showID == show.id else { return nil }
        return spotlight.roleLine
    }
}
