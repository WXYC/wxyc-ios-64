//
//  SpecialtyCard.swift
//  Playlist
//
//  What a specialty program's card shows and where it sits, derived from the
//  playlist's on-air state and its now-playing lead.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A specialty program's card: shown only when a DJ signed on as the specialty show.
public struct SpecialtyCard: Sendable, Equatable {
    public enum Placement: Sendable, Equatable {
        /// The show logs songs: the card heads the song list for the whole show.
        case aboveSongList
        /// The show logs none: the card is the now-playing item.
        case nowPlaying
    }

    public let program: SpecialtyShowRef
    /// The open show's own name (`on_air.show_name`), shown as a subtitle.
    public let showName: String?
    public let djHandle: String
    public let placement: Placement
    /// Whether the tagline shows: until the first song (or who's-on entry) of the open show.
    public let showsTagline: Bool
    /// Whether the card draws its own "now playing" header. Only when it is the now-playing item
    /// and no song leads: a show that logs no songs but logs one anyway has a leading song, which
    /// takes the one "now playing" header (``Playlist/sections(of:lead:)``).
    public let showsNowPlayingHeader: Bool

    public init(program: SpecialtyShowRef, showName: String?, djHandle: String, placement: Placement, showsTagline: Bool, showsNowPlayingHeader: Bool) {
        self.program = program
        self.showName = showName
        self.djHandle = djHandle
        self.placement = placement
        self.showsTagline = showsTagline
        self.showsNowPlayingHeader = showsNowPlayingHeader
    }
}

public extension Playlist {
    /// The specialty card to show, or `nil` for a freeform show, automation, or unknown on-air.
    /// An unspecified `logs_playcuts` keeps the song list, so a song that lands is never hidden.
    var specialtyCard: SpecialtyCard? {
        guard case .dj(let handle, let show?) = onAir, let program = show.specialty else { return nil }
        let showsTagline = if case .specialtyCard = nowPlayingLead { true } else { false }
        let songLeads = if case .song = nowPlayingLead { true } else { false }
        let placement: SpecialtyCard.Placement = program.logsPlaycuts == false ? .nowPlaying : .aboveSongList
        return SpecialtyCard(
            program: program,
            showName: show.title,
            djHandle: handle,
            placement: placement,
            showsTagline: showsTagline,
            showsNowPlayingHeader: placement == .nowPlaying && !songLeads
        )
    }
}

public extension SpecialtyShowRef {
    /// The text a tile is drawn with when the program has no logo.
    var tileText: String { shortName ?? name }

    /// The accent color's components in `0...1`, or `nil` when absent or not a six-digit hex.
    var accentRGB: (red: Double, green: Double, blue: Double)? {
        guard let hex = accentColor?.drop(while: { $0 == "#" }), hex.count == 6,
              let value = UInt32(hex, radix: 16) else { return nil }
        return (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}
