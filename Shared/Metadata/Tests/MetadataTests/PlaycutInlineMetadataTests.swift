//
//  PlaycutInlineMetadataTests.swift
//  Metadata
//
//  Tests for the `metadataStatus`-driven branching that decides whether
//  PlaycutDetailView can render inline V2 row metadata or must fall back
//  to /proxy/metadata/album. Covers all five enum cases plus nil.
//
//  Created by Jake Bromberg on 06/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Playlist
import PlaylistTesting
@testable import Metadata

@Suite("PlaycutInlineMetadata branching (#270)")
struct PlaycutInlineMetadataTests {

    // MARK: - Enriched states: render inline, no proxy fetch

    @Test("enriched_match returns inline PlaycutMetadata composed from row fields")
    func enrichedMatchReturnsInline() throws {
        let playcut = Self.enrichedPlaycut(status: .enrichedMatch)
        let inline = try #require(PlaycutInlineMetadata.from(playcut))

        #expect(inline.album.label == "Sonamos")
        #expect(inline.album.releaseYear == 2022)
        #expect(inline.album.discogsURL?.absoluteString == "https://www.discogs.com/release/27500000")
        #expect(inline.artistBio == "Argentine singer-songwriter.")
        #expect(inline.streaming.spotifyURL?.absoluteString == "https://open.spotify.com/track/example")
    }

    @Test("enriched_no_match returns inline PlaycutMetadata (synthesized streaming only)")
    func enrichedNoMatchReturnsInline() throws {
        // Synthesized streaming-only shape: bandcamp/soundcloud/youtube but no
        // Discogs metadata. This is the canonical enriched_no_match output.
        let playcut = Playcut.stub(
            songTitle: "Aluminum Tunes",
            labelName: "Duophonic",
            artistName: "Stereolab",
            releaseTitle: "Aluminum Tunes",
            metadataStatus: .enrichedNoMatch
        )
        // Synthesize the streaming-only fields on a fresh Playcut.
        let row = Self.streamingOnlyPlaycut(
            base: playcut,
            youtubeMusicURL: URL(string: "https://music.youtube.com/search?q=Stereolab"),
            bandcampURL: URL(string: "https://bandcamp.com/search?q=Stereolab"),
            soundcloudURL: URL(string: "https://soundcloud.com/search?q=Stereolab")
        )

        let inline = try #require(PlaycutInlineMetadata.from(row))

        #expect(inline.album.discogsURL == nil)
        #expect(inline.album.releaseYear == nil)
        #expect(inline.artistBio == nil)
        #expect(inline.streaming.youtubeMusicURL != nil)
        #expect(inline.streaming.bandcampURL != nil)
        #expect(inline.streaming.soundcloudURL != nil)
    }

    @Test("failed_no_retry returns inline PlaycutMetadata (terminal, no fetch)")
    func failedNoRetryReturnsInline() throws {
        // failed_no_retry rows are operationally terminal — render whatever is
        // on the row (which is typically just synthesized search URLs).
        let playcut = Playcut.stub(
            songTitle: "Moon Pix",
            labelName: "Matador Records",
            artistName: "Cat Power",
            releaseTitle: "Moon Pix",
            metadataStatus: .failedNoRetry
        )

        let inline = try #require(PlaycutInlineMetadata.from(playcut))

        // The label is still surfaced from the flowsheet row even though
        // enrichment failed.
        #expect(inline.album.label == "Matador Records")
    }

    // MARK: - In-flight / unknown states: fall back to the proxy fetch

    @Test("pending returns nil (caller falls back to /proxy/metadata/album)")
    func pendingReturnsNil() {
        let playcut = Playcut.stub(metadataStatus: .pending)
        #expect(PlaycutInlineMetadata.from(playcut) == nil)
    }

    @Test("enriching returns nil (caller falls back to /proxy/metadata/album)")
    func enrichingReturnsNil() {
        let playcut = Playcut.stub(metadataStatus: .enriching)
        #expect(PlaycutInlineMetadata.from(playcut) == nil)
    }

    @Test("nil metadataStatus returns nil (V1 row / pre-Epic-C deploy)")
    func nilStatusReturnsNil() {
        let playcut = Playcut.stub(metadataStatus: nil)
        #expect(PlaycutInlineMetadata.from(playcut) == nil)
    }

    // MARK: - Helpers

    private static func enrichedPlaycut(status: MetadataStatus) -> Playcut {
        Playcut(
            id: 5_194_726,
            hour: 1000,
            chronOrderID: 5_194_726,
            timeCreated: 1000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            artworkURL: URL(string: "https://example.com/doga.jpg"),
            discogsURL: URL(string: "https://www.discogs.com/release/27500000"),
            releaseYear: 2022,
            spotifyURL: URL(string: "https://open.spotify.com/track/example"),
            appleMusicURL: URL(string: "https://music.apple.com/us/album/example"),
            youtubeMusicURL: nil,
            bandcampURL: URL(string: "https://juanamolina.bandcamp.com/track/la-paradoja"),
            soundcloudURL: nil,
            artistBio: "Argentine singer-songwriter.",
            artistWikipediaURL: URL(string: "https://en.wikipedia.org/wiki/Juana_Molina"),
            metadataStatus: status
        )
    }

    private static func streamingOnlyPlaycut(
        base: Playcut,
        youtubeMusicURL: URL? = nil,
        bandcampURL: URL? = nil,
        soundcloudURL: URL? = nil
    ) -> Playcut {
        Playcut(
            id: base.id,
            hour: base.hour,
            chronOrderID: base.chronOrderID,
            timeCreated: base.timeCreated,
            songTitle: base.songTitle,
            labelName: base.labelName,
            artistName: base.artistName,
            releaseTitle: base.releaseTitle,
            youtubeMusicURL: youtubeMusicURL,
            bandcampURL: bandcampURL,
            soundcloudURL: soundcloudURL,
            metadataStatus: base.metadataStatus
        )
    }
}
