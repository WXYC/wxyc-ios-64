//
//  PlaylistSection.swift
//  Playlist
//
//  Which playlist rows open the "now playing" and "recently played" sections.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A section a playlist row can open. See ``Playlist/sections(of:lead:)``.
public enum PlaylistSection: Sendable, Equatable {
    case nowPlaying
    case recentlyPlayed
}

/// What the large widget shows. See ``Playlist/widgetContent(lead:hasRecents:)``.
public enum WidgetContent: Sendable, Equatable {
    /// A leading song, with the recents under it.
    case lead
    /// A leading song during a specialty show: the same, with the program as context.
    case leadInProgram
    /// A specialty show with no song of its own yet: the program over the person, with the recents under it.
    case program
    /// A who's-on entry leads: its line takes the lead line, with the recents under it.
    case whosOn
    /// No song leads but recents exist: the station line, with the recents under it.
    case stationLine
    /// Nothing to show: the empty state.
    case empty
}

public extension WidgetContent {
    /// How many recents the widget shows under this layout. A specialty show's layouts show two ("Recently
    /// Played drops to two rows"); every other layout shows up to three, which `Playlist.widgetRecents` supplies.
    var recentLimit: Int {
        switch self {
        case .leadInProgram, .program: 2
        case .lead, .whosOn, .stationLine, .empty: 3
        }
    }
}

public extension Playlist {
    /// The widget's lead line when no song leads and nobody has to be named on a guess.
    static let tuneInLine = "Tune in to WXYC 89.3 FM"

    /// The line the widget leads with when no song leads: whoever the on-air banner names, so the
    /// widget never says less than the app does two inches away. A named DJ's handle while one is
    /// live, "Auto DJ" under confirmed automation, and ``tuneInLine`` when the backend reports no
    /// on-air status at all — the one state where naming anybody would be a guess, which is exactly
    /// why ``OnAir/bannerTitle`` is `nil` there rather than "Auto DJ".
    var widgetStationLine: String {
        onAir.bannerTitle ?? Self.tuneInLine
    }

    /// The rows that open a section, keyed by playcut id.
    ///
    /// Only a leading song or who's-on entry opens "now playing". "Recently played" opens on the first
    /// non-leading playcut in `items` order, which is not necessarily the second playcut:
    /// the leader comes from ``currentPlaycut`` and can sort anywhere in the timeline.
    /// Computed once per playlist so a render compares ids instead of rescanning per row.
    static func sections(of items: [TimelineItem], lead: NowPlayingLead) -> [UInt64: PlaylistSection] {
        var sections: [UInt64: PlaylistSection] = [:]
        var leaderID: UInt64?
        switch lead {
        case .song(let leader):
            leaderID = leader.id
            sections[leader.id] = .nowPlaying
        case .spotlight(let entry):
            sections[entry.id] = .nowPlaying
        case .specialtyCard, .djHandle, .nothing:
            break
        }
        let firstRecent = items.lazy
            .compactMap { item -> Playcut? in
                if case .playcut(let playcut) = item { playcut } else { nil }
            }
            .first { $0.id != leaderID }
        if let firstRecent {
            sections[firstRecent.id] = .recentlyPlayed
        }
        return sections
    }

    /// The widget's recent songs, newest first: up to three, skipping the leading song.
    static func widgetRecents(of playcuts: [Playcut], lead: NowPlayingLead) -> [Playcut] {
        let leaderID: UInt64? = switch lead {
        case .song(let leader): leader.id
        case .spotlight, .specialtyCard, .djHandle, .nothing: nil
        }
        return Array(playcuts.sorted(by: >).filter { $0.id != leaderID }.prefix(3))
    }

    /// Which of the widget's layouts to show. A leading song or who's-on entry wins, a specialty show
    /// with no song yet shows its program; otherwise recents under the station line; the empty state
    /// only when there is nothing at all. `program` is the specialty show on the air whose layouts to use; `nil`
    /// keeps the freeform layouts, which is what a surface without specialty layouts passes (the large widget, until
    /// WXYC/wxyc-ios-64#1217).
    static func widgetContent(lead: NowPlayingLead, hasRecents: Bool, program: SpecialtyShowRef?) -> WidgetContent {
        switch lead {
        case .song: program == nil ? .lead : .leadInProgram
        case .spotlight: .whosOn
        case .specialtyCard: program == nil ? (hasRecents ? .stationLine : .empty) : .program
        case .djHandle, .nothing: hasRecents ? .stationLine : .empty
        }
    }
}
