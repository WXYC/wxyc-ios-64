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
//  is what makes free-text likes eligible for the For You shelf (#493).
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

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

    /// Observation-time id healing: any id-bearing playcut whose folded artist
    /// name matches a nil-id liked row stamps that id onto the row. `likedAt`
    /// is preserved; rows that already carry an id are never touched. Saves
    /// only when something changed.
    public func heal(from playcuts: [Playcut]) {
        var idsByFoldedArtist: [String: Int] = [:]
        for playcut in playcuts {
            if let artistId = playcut.artistId {
                idsByFoldedArtist[SongKey.fold(playcut.artistName)] = artistId
            }
        }
        guard !idsByFoldedArtist.isEmpty else { return }

        var changed = false
        for index in songs.indices where songs[index].artistId == nil {
            if let artistId = idsByFoldedArtist[SongKey.fold(songs[index].artistName)] {
                songs[index].artistId = artistId
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Distinct catalog artist ids across liked songs — the For You shelf's
    /// taste signal (#493).
    public var likedArtistIds: Set<Int> {
        Set(songs.compactMap(\.artistId))
    }

    /// The store size as a coarse analytics bucket ("0", "1-9", "10-49",
    /// "50+") — volume without identity, per the privacy invariant.
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
