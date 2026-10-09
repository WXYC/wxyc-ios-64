//
//  SongKey.swift
//  LikedSongs
//
//  Folded song identity for the on-device likes store: a liked song is keyed
//  by folded(artistName) + folded(songTitle) — case-, diacritic-, and
//  width-insensitive with whitespace collapsed — so the linked play, the
//  ALL-CAPS free-text replay, and the single vs. LP cut of the same song
//  dedupe to one row. The album is deliberately excluded from identity, and
//  the catalog artistId is an attribute, never part of the key (#492).
//  `releaseKey` is the separate, release-level key that album-id healing
//  matches on (#1151).
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public enum SongKey {

    /// Locale pinned for the case/diacritic folding so the dedupe key is
    /// identical on every device — a Turkish-locale device must not fold
    /// "I"/"i" differently than everyone else. Mirrors the `en_US_POSIX`
    /// pinning of the Playlist package's locale-sensitive string work.
    private static let foldingLocale = Locale(identifier: "en_US_POSIX")

    /// Case/diacritic/width-insensitive fold with whitespace collapsed and
    /// trimmed. "NILÜFER  Yanya" and "nilufer yanya" fold identically.
    public static func fold(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: foldingLocale)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The store key for a song: folded artist and folded title, joined with a
    /// separator that can't collide with the folded segments' content in
    /// practice ("|" survives folding untouched but never terminates a fold).
    public static func key(artist: String, title: String) -> String {
        fold(artist) + "|" + fold(title)
    }

    /// A release's identity for album-id healing: folded artist and folded
    /// release title, kept as separate fields so a separator inside either
    /// name can't make two releases collide.
    struct ReleaseKey: Hashable, Sendable {
        let artist: String
        let release: String
    }

    /// The release key for an artist and release title, or `nil` without a
    /// non-blank release title.
    static func releaseKey(artist: String, release: String?) -> ReleaseKey? {
        releaseKey(foldedArtist: fold(artist), release: release)
    }

    /// ``releaseKey(artist:release:)`` for a caller that has already folded
    /// the artist name.
    static func releaseKey(foldedArtist: String, release: String?) -> ReleaseKey? {
        guard let release else { return nil }
        let folded = fold(release)
        guard !folded.isEmpty else { return nil }
        return ReleaseKey(artist: foldedArtist, release: folded)
    }
}
