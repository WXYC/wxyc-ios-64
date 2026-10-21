//
//  NowPlayingLead.swift
//  Playlist
//
//  The pure rule that decides what leads the now-playing surfaces: a song, a
//  specialty show's card, a DJ's handle, or nothing.
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
    /// Nothing leads: automation, or no song and no on-air information. Named `nothing`, not
    /// `none`, so `.none` on an optional lead is never ambiguous with `Optional.none`.
    case nothing
}

public extension Playlist {
    /// What leads now playing, given the newest song (``currentPlaycut``) and who is on the air.
    ///
    /// A song leads only when it belongs to the open show, so a new show with no song yet does
    /// not inherit the previous show's last song. A playcut with no show id (an old cache
    /// entry) cannot be shown to belong, so it never leads once the open show's id is known.
    /// Automation leads with nothing. When the backend does not say which show is open
    /// (`unknown`, or a show with no id) the newest song leads, falling back to the show's
    /// specialty card or the DJ handle when there is no song.
    ///
    /// This is a pure rule: no surface reads it yet.
    var nowPlayingLead: NowPlayingLead {
        let newest = currentPlaycut
        switch onAir {
        case .automation:
            return .nothing
        case .unknown:
            return newest.map { .song($0) } ?? .nothing
        case .dj(let name, let show):
            let fallback: NowPlayingLead = show?.specialty.map { .specialtyCard($0) } ?? .djHandle(name)
            guard let showID = show?.id else {
                return newest.map { .song($0) } ?? fallback
            }
            if let newest, newest.showID == showID {
                return .song(newest)
            }
            return fallback
        }
    }
}
