//
//  NowPlayingLead.swift
//  Playlist
//
//  What leads the now-playing surfaces: a song, a specialty show's card, a DJ's
//  handle, or nothing.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// What leads now playing. See ``Playlist/nowPlayingLead``.
public enum NowPlayingLead: Sendable, Equatable {
    /// The open show's current song.
    case song(Playcut)
    /// A specialty show with no song yet; the card carries the show's `tagline`.
    case specialtyCard(SpecialtyShowRef)
    /// A freeform show with no song yet.
    case djHandle(String)
    /// Automation: nothing leads.
    case none
}

/// The two lines a surface without a song to show prints for a non-song lead.
public struct NowPlayingHeadline: Sendable, Equatable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public extension NowPlayingLead {
    /// What to print when this lead is not a song: the DJ or specialty show on the air, or
    /// the automation line. `nil` for a song, which prints itself.
    var headline: NowPlayingHeadline? {
        switch self {
        case .song:
            nil
        case .specialtyCard(let show):
            NowPlayingHeadline(title: show.name, detail: show.tagline ?? "is on the air")
        case .djHandle(let name):
            NowPlayingHeadline(title: name, detail: "is on the air")
        case .none:
            NowPlayingHeadline(title: "Auto DJ", detail: "Tune in to WXYC 89.3 FM")
        }
    }
}

/// The header above a playcut row in the playlist.
public enum PlaylistSection: Sendable, Equatable {
    case nowPlaying
    case recentlyPlayed
}

public extension Playlist {
    /// The section header for the playcut at `index` (counting playcuts only, newest first)
    /// with the given `id`, or `nil` when it takes none.
    ///
    /// Only the leading song is "now playing", so a previous show's last song is never
    /// labelled so. "Recently played" opens on the first playcut after the leader, or on the
    /// first playcut when no song leads.
    func section(forPlaycutAt index: Int, id: UInt64) -> PlaylistSection? {
        let leading = currentPlaycut
        if let leading, leading.id == id {
            return .nowPlaying
        }
        return index == (leading == nil ? 0 : 1) ? .recentlyPlayed : nil
    }

    /// The up-to-three playcuts the widget lists under its lead: the newest, minus the
    /// leading song when one leads.
    var widgetRecents: [Playcut] {
        let leadingID = currentPlaycut?.id
        return Array(playcuts.sorted(by: >).filter { $0.id != leadingID }.prefix(3))
    }
}
