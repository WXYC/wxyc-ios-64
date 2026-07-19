//
//  LikedSongSnapshot.swift
//  LikedSongs
//
//  The persisted shape of a liked song: a lean snapshot of the playcut's
//  display fields taken at like time, plus `likedAt`. Deliberately NOT a raw
//  `Playcut` — that would also serialize `artistBio`, `genres`, `styles`, and
//  the embedded `upcomingShow`, several KB per like that the Liked tab never
//  reads. `toPlaycut()` bridges back for the standard detail card, which by
//  the v1 decision renders without a Box Office ticket (concert surfacing for
//  liked artists is the For You shelf's job, #493).
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist

public struct LikedSongSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let songTitle: String
    public let artistName: String

    /// Resolved catalog artist id (`artists.id` keyspace). Nil when the like
    /// came from a free-text play or the v1 API; healed later by
    /// ``LikedSongsStore/heal(from:)`` when an id-bearing play of the same
    /// folded artist name is observed.
    public internal(set) var artistId: Int?

    public let releaseTitle: String?
    public let labelName: String?
    public let artworkURL: URL?
    public let discogsURL: URL?
    public let spotifyURL: URL?
    public let appleMusicURL: URL?
    public let youtubeMusicURL: URL?
    public let bandcampURL: URL?
    public let soundcloudURL: URL?
    public let likedAt: Date

    /// Folded song identity — see ``SongKey``. Also the stable SwiftUI identity.
    public var key: String { SongKey.key(artist: artistName, title: songTitle) }
    public var id: String { key }

    public init(playcut: Playcut, likedAt: Date) {
        self.songTitle = playcut.songTitle
        self.artistName = playcut.artistName
        self.artistId = playcut.artistId
        self.releaseTitle = playcut.releaseTitle
        self.labelName = playcut.labelName
        self.artworkURL = playcut.artworkURL
        self.discogsURL = playcut.discogsURL
        self.spotifyURL = playcut.spotifyURL
        self.appleMusicURL = playcut.appleMusicURL
        self.youtubeMusicURL = playcut.youtubeMusicURL
        self.bandcampURL = playcut.bandcampURL
        self.soundcloudURL = playcut.soundcloudURL
        self.likedAt = likedAt
    }

    /// Bridges back to a `Playcut` for the standard detail card. The flowsheet
    /// identity fields are synthesized (`id`/`chronOrderID` are 0; the hour is
    /// the like instant) — the detail card reads only display fields, and list
    /// identity uses ``id``, so no consumer keys on them.
    public func toPlaycut() -> Playcut {
        let likedAtMillis = UInt64(max(0, likedAt.timeIntervalSince1970 * 1000))
        return Playcut(
            id: 0,
            hour: likedAtMillis,
            chronOrderID: 0,
            timeCreated: likedAtMillis,
            songTitle: songTitle,
            labelName: labelName,
            artistName: artistName,
            releaseTitle: releaseTitle,
            artworkURL: artworkURL,
            discogsURL: discogsURL,
            spotifyURL: spotifyURL,
            appleMusicURL: appleMusicURL,
            youtubeMusicURL: youtubeMusicURL,
            bandcampURL: bandcampURL,
            soundcloudURL: soundcloudURL,
            artistId: artistId
        )
    }
}
