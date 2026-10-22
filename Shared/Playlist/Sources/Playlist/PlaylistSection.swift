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

/// What the large widget shows. See ``Playlist/widgetContent(hasLead:hasRecents:)``.
public enum WidgetContent: Sendable, Equatable {
    /// A leading song, with the recents under it.
    case lead
    /// No song leads but recents exist: the station line, with the recents under it.
    case stationLine
    /// Nothing to show: the empty state.
    case empty
}

public extension Playlist {
    /// The rows that open a section, keyed by playcut id.
    ///
    /// Only a leading song opens "now playing". "Recently played" opens on the first
    /// non-leading playcut in `items` order, which is not necessarily the second playcut:
    /// the leader comes from ``currentPlaycut`` and can sort anywhere in the timeline.
    /// Computed once per playlist so a render compares ids instead of rescanning per row.
    static func sections(of items: [TimelineItem], lead: NowPlayingLead) -> [UInt64: PlaylistSection] {
        var sections: [UInt64: PlaylistSection] = [:]
        var leaderID: UInt64?
        if case .song(let leader) = lead {
            leaderID = leader.id
            sections[leader.id] = .nowPlaying
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
        var leaderID: UInt64?
        if case .song(let leader) = lead {
            leaderID = leader.id
        }
        return Array(playcuts.sorted(by: >).filter { $0.id != leaderID }.prefix(3))
    }

    /// Which of the widget's three layouts to show. A leading song wins; otherwise recents
    /// under the station line; the empty state only when there is nothing at all.
    static func widgetContent(hasLead: Bool, hasRecents: Bool) -> WidgetContent {
        if hasLead {
            return .lead
        }
        return hasRecents ? .stationLine : .empty
    }
}
