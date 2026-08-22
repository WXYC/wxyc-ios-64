//
//  LikableSong.swift
//  LikedSongs
//
//  `SongDisplayable` plus the catalog artist id. The two types a like acts on
//  — a live `Playcut` and the persisted `LikedSongSnapshot` taken from it —
//  already present identically through `SongDisplayable`, but that protocol is
//  deliberately narrow to what a row renders and stops short of `artistId`,
//  which nothing rendered needed. The like path is the first reader that does.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist

/// A song a listener can like, in the two shapes the app holds one in.
///
/// Refines ``Playlist/SongDisplayable`` with the resolved catalog artist id, so
/// the like path has a single generic body over both the live feed's `Playcut`
/// and the persisted `LikedSongSnapshot` instead of one copy per type.
public protocol LikableSong: SongDisplayable {
    /// Resolved catalog artist id (`artists.id` keyspace), or nil for a
    /// free-text or V1 play.
    var artistId: Int? { get }
}

extension Playcut: LikableSong {}

extension LikedSongSnapshot: LikableSong {}
