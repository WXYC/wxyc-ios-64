//
//  LikedSongsEvents.swift
//  Analytics
//
//  Structured analytics for on-device song likes (#492). As of the 2026-08-21
//  product reversal (docs/plans/likes-identity-capture.md) this event carries
//  song/artist/album identity alongside the lifecycle strings and coarse
//  store-size bucket — WXYC wants to know which songs, albums, and artists
//  listeners like. Hand-written rather than `@AnalyticsEvent`: the macro
//  expansion emits a flat dictionary literal with no nil handling, so an
//  `Int?` artistId would serialize as an `Optional`-wrapped `Any` instead of
//  being omitted. Follows the `ErrorEvent` precedent (`ErrorEvents.swift`).
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Event fired when a listener likes or unlikes a song. `action` is "like" or
/// "unlike"; `surface` is where the gesture happened ("row", "detail",
/// "liked_tab"); `totalBucket` is the post-toggle store size as a coarse
/// bucket ("0", "1-9", "10-49", "50+") so habit retention is visible
/// independent of identity. `songTitle`/`artist`/`album` match the shape the
/// three other identity-bearing events already use (`album` non-optional,
/// coalesced to `""` when the playcut has no release title) so a query
/// unioning "liked" against "viewed" artists needs no `coalesce`. `artistId`
/// is the one field that stays optional-and-omitted: it has no sibling across
/// those events, and absent-vs-unresolved is a real distinction.
public struct SongLikeToggled: AnalyticsEvent {
    public static let name = "song_like_toggled"

    public let action: String
    public let surface: String
    public let totalBucket: String
    public let songTitle: String
    public let artist: String
    public let album: String
    public let artistId: Int?

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "action": action,
            "surface": surface,
            "total_bucket": totalBucket,
            "song_title": songTitle,
            "artist": artist,
            "album": album,
        ]
        if let artistId { props["artist_id"] = artistId }
        return props
    }

    public init(
        action: String,
        surface: String,
        totalBucket: String,
        songTitle: String,
        artist: String,
        album: String,
        artistId: Int? = nil
    ) {
        self.action = action
        self.surface = surface
        self.totalBucket = totalBucket
        self.songTitle = songTitle
        self.artist = artist
        self.album = album
        self.artistId = artistId
    }
}
