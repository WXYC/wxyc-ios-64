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
}
