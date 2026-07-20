//
//  SongDisplayable.swift
//  Playlist
//
//  The presentation surface shared by the flowsheet's `Playcut` and the Liked
//  tab's `LikedSongSnapshot`: exactly the fields a row's title/artist column and
//  the artwork cache key read. It is intentionally NOT the full intersection of
//  the two models — only the members with a real reader through the protocol —
//  and it deliberately does not merge the models, which keep their own
//  lifecycles, identities, and persisted fields.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A song as a list row presents it. Conformed by `Playcut` (live feed) and
/// `LikedSongSnapshot` (persisted favorite) so both surfaces share one text
/// column and one artwork cache key.
///
/// Deliberately narrow: it declares only what `SongInfoColumn` and
/// ``artworkCacheKey`` read. Flowsheet-only fields (`timeCreated`, `rotation`)
/// and like-only fields (`likedAt`) stay on the concrete types — those are the
/// parts the two rows *should* render differently.
public protocol SongDisplayable: Sendable {
    var songTitle: String { get }
    var artistName: String { get }
    var releaseTitle: String? { get }
}

public extension SongDisplayable {
    /// Cache key for artwork lookups, from artist and release/song title.
    ///
    /// Uses `releaseTitle` when non-empty, otherwise falls back to `songTitle`,
    /// so the key is stable whether `releaseTitle` is `nil` or an empty string.
    /// Because both conformers derive it the same way, a `Playcut` and the
    /// `LikedSongSnapshot` taken from it resolve the identical key — the two
    /// lists hit the same cached artwork.
    var artworkCacheKey: String {
        let release = releaseTitle.flatMap { $0.isEmpty ? nil : $0 } ?? songTitle
        return "\(artistName)-\(release)"
    }
}

extension Playcut: SongDisplayable {}
