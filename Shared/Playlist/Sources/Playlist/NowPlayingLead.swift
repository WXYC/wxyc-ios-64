//
//  NowPlayingLead.swift
//  Playlist
//
//  The pure rule that decides what leads the now-playing surfaces: a song, a who's-on
//  entry, a specialty show's card, a DJ's handle, or nothing.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// What leads now playing. See ``Playlist/nowPlayingLead``.
public enum NowPlayingLead: Sendable, Equatable {
    /// The open show's current song.
    case song(Playcut)
    /// The open show's current who's-on entry, newer than its current song (or with no song yet).
    case spotlight(SpotlightEntry)
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
    /// A who's-on entry of the open show leads when it is newer than the show's current song, or
    /// the show has no song yet; the next song takes the lead back. A `host` entry never leads,
    /// and an entry from another show, or on a show with no id, cannot be placed and does not.
    /// Automation leads with nothing. When the backend does not say which show is open
    /// (`unknown`, or a show with no id) the newest song leads, falling back to the show's
    /// specialty card or the DJ handle when there is no song.
    ///
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
            let spotlight = show?.spotlight.flatMap { $0.showID == showID && !$0.isHost ? $0 : nil }
            if let newest, newest.showID == showID {
                if let spotlight, spotlight.chronOrderID > newest.chronOrderID {
                    return .spotlight(spotlight)
                }
                return .song(newest)
            }
            return spotlight.map { .spotlight($0) } ?? fallback
        }
    }
}

/// What the system Now Playing info and the widget say while a who's-on entry leads.
public struct NowPlayingSpotlight: Sendable, Equatable {
    /// Where the artwork comes from: never the previous song's album art.
    public enum Artwork: Sendable, Equatable {
        /// A specialty show keeps the program first, with the program's own artwork.
        case program(SpecialtyShowRef)
        /// A freeform show uses the app's station artwork.
        case station
    }

    public let title: String
    public let artist: String
    /// The album line outside a song.
    public let album: String
    public let artwork: Artwork

    public init(title: String, artist: String, album: String, artwork: Artwork) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
    }
}

public extension Playlist {
    /// The Now Playing info strings while a who's-on entry leads, or `nil` when none does.
    ///
    /// A specialty show keeps the program as the title and puts the person as the artist; a
    /// freeform show puts the role line over the DJ handle.
    var nowPlayingSpotlight: NowPlayingSpotlight? {
        guard case .spotlight(let entry) = nowPlayingLead, case .dj(let handle, let show) = onAir,
              let roleLine = entry.roleLine else { return nil }
        if let program = show?.specialty {
            return NowPlayingSpotlight(title: program.name, artist: entry.name, album: "WXYC 89.3 FM", artwork: .program(program))
        }
        return NowPlayingSpotlight(title: roleLine, artist: handle, album: "WXYC 89.3 FM", artwork: .station)
    }
}
