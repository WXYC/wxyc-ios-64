//
//  LikeAnalyticsFields.swift
//  LikedSongs
//
//  Pure toggle -> analytics-field mapping for the like/unlike event (2026-08-21
//  identity reversal, docs/plans/likes-identity-capture.md). Lives here rather
//  than as a private method on the SwiftUI views that call it: a view's
//  `toggleLike()` is unreachable from `WXYCTests`, and the repo's working
//  precedent for testing logic in these exact views is a pure static
//  (`LikeHeartButton.shouldCelebrate(from:to:reduceMotion:)`). This type lets
//  the views become a mechanical mapping with no branching, while everything
//  that can actually be wrong — like-vs-unlike, nil artistId, empty-album
//  coalescing, field transposition — is covered here in `LikedSongsTests`.
//
//  `LikedSongs` must not gain an `Analytics` dependency to host this — that
//  would put PostHog in every `LikedSongs` consumer's build graph. This type
//  is deliberately analytics-agnostic: `SongLikeToggled` (in `Analytics`)
//  reads these fields, not the other way around.
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

    /// Derives fields from the playcut a row/detail toggle acted on.
    ///
    /// Takes the post-toggle liked state rather than an already-formatted
    /// action string: the `"like"`/`"unlike"` spelling is the part of the
    /// mapping that can silently drift (a call site typing `"liked"` would
    /// split the PostHog `action` dimension without failing anything), so it
    /// is derived here once and pinned by test, not retyped at three sites.
    public static func make(from playcut: Playcut, liked: Bool) -> LikeAnalyticsFields {
        LikeAnalyticsFields(
            action: action(liked: liked),
            songTitle: playcut.songTitle,
            artist: playcut.artistName,
            album: playcut.releaseTitle ?? "",
            artistId: playcut.artistId
        )
    }

    /// Derives fields from a persisted snapshot — the Liked tab's unlike path,
    /// which acts on a `LikedSongSnapshot` rather than a live `Playcut`.
    public static func make(from snapshot: LikedSongSnapshot, liked: Bool) -> LikeAnalyticsFields {
        LikeAnalyticsFields(
            action: action(liked: liked),
            songTitle: snapshot.songTitle,
            artist: snapshot.artistName,
            album: snapshot.releaseTitle ?? "",
            artistId: snapshot.artistId
        )
    }

    /// The wire spelling of the post-toggle state. Sole definition of these
    /// two strings.
    private static func action(liked: Bool) -> String {
        liked ? "like" : "unlike"
    }
}
