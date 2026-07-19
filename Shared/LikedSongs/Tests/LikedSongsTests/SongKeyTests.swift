//
//  SongKeyTests.swift
//  LikedSongs
//
//  Folding and key identity: case, diacritics, whitespace, width, and the
//  Turkish-İ locale trap are all folded away so the same song deduplicates
//  across linked plays, free-text replays, and release variants.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import LikedSongs

@Suite("SongKey Tests")
struct SongKeyTests {

    @Test("Folding is case-, diacritic-, and whitespace-insensitive", arguments: [
        ("Nilüfer  Yanya", "nilufer yanya"),
        ("CHUQUIMAMANI-CONDORI", "chuquimamani-condori"),
        ("  Jessica   Pratt ", "jessica pratt"),
        ("Hermanos Gutiérrez", "hermanos gutierrez"),
        ("İSTANBUL", "istanbul"),
    ])
    func folds(input: String, expected: String) {
        #expect(SongKey.fold(input) == expected)
    }

    @Test("Keys match across casing, diacritics, and spacing of the same song")
    func keysMatch() {
        #expect(
            SongKey.key(artist: "NILÜFER YANYA", title: "MIDNIGHT  SUN")
                == SongKey.key(artist: "Nilüfer Yanya", title: "Midnight Sun")
        )
    }

    @Test("Different artists or titles produce different keys")
    func keysDiffer() {
        #expect(
            SongKey.key(artist: "Stereolab", title: "Metronomic Underground")
                != SongKey.key(artist: "Stereolab", title: "Percolator")
        )
        #expect(
            SongKey.key(artist: "Juana Molina", title: "la paradoja")
                != SongKey.key(artist: "Jessica Pratt", title: "la paradoja")
        )
    }
}
