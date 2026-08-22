//
//  SongLikeToggled+LikeAnalyticsFields.swift
//  WXYC
//
//  The one bridge between `LikeAnalyticsFields` (LikedSongs) and
//  `SongLikeToggled` (Analytics). Neither package may depend on the other, so
//  the app target — which imports both — is the only place the two types can
//  meet. Top-level rather than under `Views/Liked/` because all three toggle
//  sites use it and two of them live elsewhere.
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
