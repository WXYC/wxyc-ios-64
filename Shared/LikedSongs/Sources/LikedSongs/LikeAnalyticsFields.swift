//
//  LikeAnalyticsFields.swift
//  LikedSongs
//
//  Pure toggle -> analytics-field mapping for the like/unlike event (2026-08-21
//  identity reversal, docs/plans/likes-identity-capture.md). It lives here, and
//  not as a private method on the SwiftUI views that call it, because a view's
//  `toggleLike()` is unreachable from tests — the same bargain
//  `LikeHeartButton.shouldCelebrate(from:to:reduceMotion:)` strikes. The views
//  are left with a mechanical call; everything that can actually be wrong is
//  covered in `LikedSongsTests`.
//
//  `LikedSongs` must not gain an `Analytics` dependency to host this — that
//  would put PostHog in every `LikedSongs` consumer's build graph. The type is
//  analytics-agnostic: `SongLikeToggled` reads these fields, not the reverse.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist

/// The field values a like/unlike toggle contributes to the `SongLikeToggled`
/// analytics event, independent of which surface (row, detail, Liked tab)
/// triggered it.
public struct LikeAnalyticsFields: Equatable, Sendable {
    /// `"like"` or `"unlike"`.
    public let action: String
    public let songTitle: String
    public let artist: String
    /// `""` when the source has no release title — matches the coalescing
    /// `PlaycutDetailViewPresented`, `StreamingLinkTapped`, and
    /// `ExternalLinkTapped` already do, so a query unioning "liked" against
    /// "viewed" artists needs no `coalesce`.
    public let album: String
    public let artistId: Int?

    public init(action: String, songTitle: String, artist: String, album: String, artistId: Int?) {
        self.action = action
        self.songTitle = songTitle
        self.artist = artist
        self.album = album
        self.artistId = artistId
    }

    /// Derives the fields from the song a toggle acted on — a live `Playcut`
    /// from the row and detail surfaces, or the persisted `LikedSongSnapshot`
    /// the Liked tab's unlike path holds.
    ///
    /// Takes the post-toggle liked state rather than an already-formatted
    /// action string: the `"like"`/`"unlike"` spelling is the part that can
    /// silently drift, so it is derived here once and pinned by test.
    public static func make(from song: some LikableSong, liked: Bool) -> LikeAnalyticsFields {
        LikeAnalyticsFields(
            action: liked ? "like" : "unlike",
            songTitle: song.songTitle,
            artist: song.artistName,
            album: song.releaseTitle ?? "",
            artistId: song.artistId
        )
    }
}
