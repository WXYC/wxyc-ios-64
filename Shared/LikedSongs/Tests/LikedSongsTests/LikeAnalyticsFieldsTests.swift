//
//  LikeAnalyticsFieldsTests.swift
//  LikedSongs
//
//  Coverage for the pure LikableSong -> LikeAnalyticsFields mapping:
//  like-vs-unlike action, nil artistId carried through unchanged, empty-album
//  coalescing, and that fields land in the right slot (no artist/songTitle
//  transposition). This is where the real test coverage for the like-analytics
//  identity work lives — the call sites that consume this type become a
//  mechanical mapping with no branching, mirroring
//  LikeHeartButton.shouldCelebrate's testability bargain.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import LikedSongs

@Suite("LikeAnalyticsFields derivation")
struct LikeAnalyticsFieldsTests {

    private static let likedAt = Date(timeIntervalSince1970: 1_000)

    // MARK: - From a Playcut

    @Test("Liking a playcut with a resolved artist id captures identity")
    func likingCapturesIdentity() {
        let playcut = Playcut.stub(
            songTitle: "Back, Baby", artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again", artistId: 812
        )

        let fields = LikeAnalyticsFields.make(from: playcut, liked: true)

        #expect(fields.action == "like")
        #expect(fields.songTitle == "Back, Baby")
        #expect(fields.artist == "Jessica Pratt")
        #expect(fields.album == "On Your Own Love Again")
        #expect(fields.artistId == 812)
    }

    @Test(
        "The post-toggle liked state derives the wire action string",
        arguments: [(true, "like"), (false, "unlike")]
    )
    func likedStateDerivesAction(liked: Bool, expected: String) {
        let playcut = Playcut.stub(songTitle: "Back, Baby", artistName: "Jessica Pratt")

        let fields = LikeAnalyticsFields.make(from: playcut, liked: liked)

        #expect(fields.action == expected)
    }

    @Test("Nil artistId is carried through as nil, not defaulted")
    func nilArtistIdCarriesThrough() {
        let playcut = Playcut.stub(songTitle: "la paradoja", artistName: "Juana Molina", artistId: nil)

        let fields = LikeAnalyticsFields.make(from: playcut, liked: true)

        #expect(fields.artistId == nil)
    }

    @Test("Missing release title coalesces album to empty string")
    func missingReleaseTitleCoalesces() {
        let playcut = Playcut.stub(songTitle: "la paradoja", artistName: "Juana Molina", releaseTitle: nil)

        let fields = LikeAnalyticsFields.make(from: playcut, liked: true)

        #expect(fields.album == "")
    }

    @Test("Fields are not transposed")
    func fieldsAreNotTransposed() {
        let playcut = Playcut.stub(
            songTitle: "Call Your Name", artistName: "Chuquimamani-Condori", releaseTitle: "Edits"
        )

        let fields = LikeAnalyticsFields.make(from: playcut, liked: true)

        #expect(fields.songTitle == "Call Your Name")
        #expect(fields.artist == "Chuquimamani-Condori")
        #expect(fields.album == "Edits")
        // Guard against a silent artist<->songTitle swap: neither should ever
        // hold the other's value.
        #expect(fields.songTitle != fields.artist)
    }

    // MARK: - From a LikedSongSnapshot (the Liked tab's unlike path)

    /// `LikedSongSnapshot` reaches the shared body through its own
    /// `LikableSong` conformance, so this guards that the conformance lands
    /// each member in the slot the `Playcut` path does.
    @Test("A snapshot derives the same fields as the playcut it was taken from")
    func snapshotDerivationMatchesPlaycut() {
        let playcut = Playcut.stub(
            songTitle: "Back, Baby", artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again", artistId: 812
        )
        let snapshot = LikedSongSnapshot(playcut: playcut, likedAt: Self.likedAt)

        let fields = LikeAnalyticsFields.make(from: snapshot, liked: false)

        #expect(fields.action == "unlike")
        #expect(fields.songTitle == "Back, Baby")
        #expect(fields.artist == "Jessica Pratt")
        #expect(fields.album == "On Your Own Love Again")
        #expect(fields.artistId == 812)
    }
}
