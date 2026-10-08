//
//  LikedSongsStore.swift
//  LikedSongs
//
//  On-device liked-songs store (#492): songs keyed by folded artist+title,
//  newest first, persisted as Codable JSON through a `FileStorage` seam.
//  Synchronous load at init and atomic write-through on mutation keep heart
//  state correct at first paint with no load/toggle race. Likes never leave
//  the device. `heal(from:)` stamps catalog artist ids onto name-only rows
//  when id-bearing plays of the same folded artist name are observed, which
//  is what makes free-text likes eligible for the For You shelf (#493), and
//  album ids onto rows saved without one, which is what gives them the detail
//  card's "Open in WXYC DJ" link (#1151).
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Logger
import Observation
import Playlist

@MainActor
@Observable
public final class LikedSongsStore {

    /// Liked songs, newest first.
    public private(set) var songs: [LikedSongSnapshot] = []

    private let storage: FileStorage
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - storage: durable byte store; production uses `AppSupportFileStorage`,
    ///     tests inject `InMemoryFileStorage`.
    ///   - now: injectable clock so tests control `likedAt` ordering.
    public init(storage: FileStorage, now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage
        self.now = now
        do {
            if let data = try storage.load() {
                songs = try JSONDecoder().decode([LikedSongSnapshot].self, from: data)
                    .sorted { $0.likedAt > $1.likedAt }
            }
        } catch {
            // Corrupt or unreadable store file: start empty rather than crash.
            // The next mutation's write-through replaces the bad bytes.
            Log(.warning, category: .caching, "Liked songs store unreadable, starting empty: \(error)")
        }
    }

    /// Whether a song with this folded identity is liked.
    public func isLiked(artistName: String, songTitle: String) -> Bool {
        index(ofKey: SongKey.key(artist: artistName, title: songTitle)) != nil
    }

    /// Likes the playcut's song if unliked, unlikes it if liked.
    /// - Returns: `true` when the result is a like, `false` for an unlike.
    @discardableResult
    public func toggle(_ playcut: Playcut) -> Bool {
        let key = SongKey.key(artist: playcut.artistName, title: playcut.songTitle)
        if let existing = index(ofKey: key) {
            songs.remove(at: existing)
            persist()
            return false
        }
        songs.insert(LikedSongSnapshot(playcut: playcut, likedAt: now()), at: 0)
        songs.sort { $0.likedAt > $1.likedAt }
        persist()
        return true
    }

    /// Removes a liked song (the Liked tab's swipe/heart-off path).
    public func unlike(_ snapshot: LikedSongSnapshot) {
        guard let existing = index(ofKey: snapshot.key) else { return }
        songs.remove(at: existing)
        persist()
    }

    /// Observation-time id healing. Any id-bearing playcut whose folded artist
    /// name matches a nil-id liked row stamps its artist id onto the row. A
    /// playcut with an album id stamps it onto a nil-album row only when the
    /// song key *and* the folded release title match: a like's identity
    /// excludes the album, so the same song from a different release must not
    /// point the row's "Open in WXYC DJ" link at an album other than the one
    /// it shows. `likedAt` is preserved; ids a row already carries are never
    /// touched. Saves only when something changed.
    public func heal(from playcuts: [Playcut]) {
        var idsByFoldedArtist: [String: Int] = [:]
        var albumIdsBySongRelease: [String: Int] = [:]
        for playcut in playcuts {
            if let artistId = playcut.artistId {
                idsByFoldedArtist[SongKey.fold(playcut.artistName)] = artistId
            }
            if let albumId = playcut.albumId, let key = Self.songReleaseKey(playcut) {
                albumIdsBySongRelease[key] = albumId
            }
        }
        guard !idsByFoldedArtist.isEmpty || !albumIdsBySongRelease.isEmpty else { return }

        var changed = false
        for index in songs.indices {
            if songs[index].artistId == nil,
               let artistId = idsByFoldedArtist[SongKey.fold(songs[index].artistName)] {
                songs[index].artistId = artistId
                changed = true
            }
            if songs[index].albumId == nil,
               let key = Self.songReleaseKey(songs[index]),
               let albumId = albumIdsBySongRelease[key] {
                songs[index].albumId = albumId
                changed = true
            }
        }
        if changed { persist() }
    }

    /// The song key plus the folded release title, or nil when there is no
    /// release to match on.
    private static func songReleaseKey(_ song: some SongDisplayable) -> String? {
        guard let releaseTitle = song.releaseTitle else { return nil }
        return SongKey.key(artist: song.artistName, title: song.songTitle) + "|" + SongKey.fold(releaseTitle)
    }

    /// Distinct catalog artist ids across liked songs — the For You shelf's
    /// taste signal (#493).
    public var likedArtistIds: Set<Int> {
        Set(songs.compactMap(\.artistId))
    }

    /// The store size as a coarse analytics bucket ("0", "1-9", "10-49",
    /// "50+"), independent of any single toggle's identity, so habit retention
    /// reads the same whatever `SongLikeToggled` carries alongside it.
    public var totalBucket: String {
        switch songs.count {
        case 0: "0"
        case 1...9: "1-9"
        case 10...49: "10-49"
        default: "50+"
        }
    }

    private func index(ofKey key: String) -> Int? {
        songs.firstIndex { $0.key == key }
    }

    private func persist() {
        do {
            try storage.save(try JSONEncoder().encode(songs))
        } catch {
            // In-memory state stays authoritative for this session; the next
            // successful write-through re-persists everything.
            Log(.warning, category: .caching, "Liked songs write-through failed: \(error)")
        }
    }
}
