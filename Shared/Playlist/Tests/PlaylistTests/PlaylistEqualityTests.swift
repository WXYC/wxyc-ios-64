//
//  PlaylistEqualityTests.swift
//  Playlist
//
//  Verifies Playlist.== reflects entry content, not just identifiers, so that
//  metadata-enriched re-fetches reach subscribers. Regression coverage for #266.
//
//  Created by Jake Bromberg on 05/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("Playlist Equality Tests")
struct PlaylistEqualityTests {

    @Test("Same entry IDs but different artwork URL are not equal")
    func metadataEnrichmentTriggersInequality() {
        let unenriched = Playlist.stub(playcuts: [
            .stub(
                id: 1,
                songTitle: "la paradoja",
                artistName: "Juana Molina",
                releaseTitle: "DOGA",
                artworkURL: nil
            )
        ])
        let enriched = Playlist.stub(playcuts: [
            .stub(
                id: 1,
                songTitle: "la paradoja",
                artistName: "Juana Molina",
                releaseTitle: "DOGA",
                artworkURL: URL(string: "https://example.com/doga.jpg")
            )
        ])

        #expect(unenriched != enriched)
    }

    @Test("Playlists with identical entries are equal")
    func identicalPlaylistsAreEqual() {
        let playcuts: [Playcut] = [
            .stub(
                id: 1,
                songTitle: "Back, Baby",
                artistName: "Jessica Pratt",
                releaseTitle: "On Your Own Love Again"
            )
        ]
        let a = Playlist.stub(playcuts: playcuts)
        let b = Playlist.stub(playcuts: playcuts)

        #expect(a == b)
    }

    @Test("Different non-playcut content with matching IDs is not equal")
    func differentBreakpointContentIsInequal() {
        let a = Playlist.stub(breakpoints: [.stub(id: 1, hour: 1000)])
        let b = Playlist.stub(breakpoints: [.stub(id: 1, hour: 2000)])

        #expect(a != b)
    }

    // The on-air broadcast gate (PlaylistService.ingest) depends on `onAir`
    // participating in `==`, so an on-air-only change reaches subscribers and the
    // banner stays live. Without this, dropping `onAir` from `==` would silently
    // reintroduce a stale-banner bug.
    @Test("Playlists differing only in onAir are not equal")
    func differentOnAirIsInequal() {
        let entries: [Playcut] = [.stub(id: 1)]
        #expect(Playlist.stub(playcuts: entries, onAir: .dj("DJ MONSTER"))
            != Playlist.stub(playcuts: entries, onAir: .automation))
        #expect(Playlist.stub(playcuts: entries, onAir: .automation)
            != Playlist.stub(playcuts: entries, onAir: .unknown))
    }

    @Test("Playlists with identical content and onAir are equal")
    func identicalOnAirIsEqual() {
        let entries: [Playcut] = [.stub(id: 1)]
        #expect(Playlist.stub(playcuts: entries, onAir: .dj("DJ MONSTER"))
            == Playlist.stub(playcuts: entries, onAir: .dj("DJ MONSTER")))
    }

    // isContentEmpty ignores onAir, so the empty-data guard still recognizes a
    // content-empty payload that carries an on-air value.
    @Test("isContentEmpty ignores onAir")
    func isContentEmptyIgnoresOnAir() {
        #expect(Playlist.stub(onAir: .dj("DJ MONSTER")).isContentEmpty)
        #expect(Playlist.stub(onAir: .automation).isContentEmpty)
        #expect(!Playlist.stub(playcuts: [.stub(id: 1)], onAir: .automation).isContentEmpty)
    }
}
