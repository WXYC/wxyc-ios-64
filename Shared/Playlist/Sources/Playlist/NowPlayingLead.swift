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
