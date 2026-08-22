//
//  SongLikeToggled+LikeAnalyticsFields.swift
//  WXYC
//
//  The one bridge between `LikeAnalyticsFields` (LikedSongs) and
//  `SongLikeToggled` (Analytics). It lives in the app target because neither
//  package may depend on the other: `Analytics` gaining `Playlist` would put
//  it in every Analytics consumer's build graph, and `LikedSongs` gaining
//  `Analytics` would put PostHog in every LikedSongs consumer's. The app
//  target already imports both, so this is the only place the two types can
//  meet.
//
//  Collapsing the expansion here is what keeps the three toggle sites from
//  each hand-writing four same-typed `String` arguments, where an
//  `artist:`/`songTitle:` transposition would compile cleanly and silently
//  swap two PostHog dimensions.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import LikedSongs

extension SongLikeToggled {
    /// Builds the event from a derived field set plus the two values only the
    /// call site knows: which surface the gesture happened on, and the
    /// post-toggle store size bucket.
    init(fields: LikeAnalyticsFields, surface: String, totalBucket: String) {
        self.init(
            action: fields.action,
            surface: surface,
            totalBucket: totalBucket,
            songTitle: fields.songTitle,
            artist: fields.artist,
            album: fields.album,
            artistId: fields.artistId
        )
    }
}
