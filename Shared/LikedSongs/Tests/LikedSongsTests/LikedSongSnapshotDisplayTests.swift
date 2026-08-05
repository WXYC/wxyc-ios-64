//
//  LikedSongSnapshotDisplayTests.swift
//  LikedSongs
//
//  Verifies that a LikedSongSnapshot presents identically to the Playcut it was
//  taken from wherever the two lists overlap — specifically that both resolve the
//  same `SongDisplayable.artworkCacheKey`, so the Liked tab and the flowsheet key
//  the same cached artwork with no `toPlaycut()` bridge needed for the key.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import LikedSongs

@Suite("LikedSongSnapshot display parity")
struct LikedSongSnapshotDisplayTests {

    private static let likedAt = Date(timeIntervalSince1970: 1_000)

    @Test("Snapshot and its source Playcut resolve the same artwork cache key")
    func artworkCacheKeyMatchesSourcePlaycut() {
        let playcut = Playcut.stub(songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: "DOGA")
        let snapshot = LikedSongSnapshot(playcut: playcut, likedAt: Self.likedAt)

        #expect(snapshot.artworkCacheKey == playcut.artworkCacheKey)
        #expect(snapshot.artworkCacheKey == "Juana Molina-DOGA")
    }

    @Test("Parity holds when the release falls back to the song title")
    func artworkCacheKeyMatchesWhenReleaseMissing() {
        // No release title: both sides must fall back to the song title.
        let playcut = Playcut.stub(songTitle: "Back, Baby", artistName: "Jessica Pratt", releaseTitle: nil)
        let snapshot = LikedSongSnapshot(playcut: playcut, likedAt: Self.likedAt)

        #expect(snapshot.artworkCacheKey == playcut.artworkCacheKey)
        #expect(snapshot.artworkCacheKey == "Jessica Pratt-Back, Baby")
    }
}
