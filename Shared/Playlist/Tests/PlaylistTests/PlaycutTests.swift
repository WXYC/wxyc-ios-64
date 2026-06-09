//
//  PlaycutTests.swift
//  Playlist
//
//  Tests for Playcut model and equality.
//
//  Created by Jake Bromberg on 01/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("Playcut Tests")
struct PlaycutTests {

    // MARK: - artworkCacheKey Tests

    @Test("artworkCacheKey uses releaseTitle when available")
    func artworkCacheKeyUsesReleaseTitle() {
        let playcut = Playcut.stub()
        #expect(playcut.artworkCacheKey == "Juana Molina-DOGA")
    }

    @Test("artworkCacheKey uses songTitle when releaseTitle is nil")
    func artworkCacheKeyUsesSongTitleWhenReleaseTitleNil() {
        let playcut = Playcut.stub(releaseTitle: nil)
        #expect(playcut.artworkCacheKey == "Juana Molina-la paradoja")
    }

    @Test("artworkCacheKey uses songTitle when releaseTitle is empty string")
    func artworkCacheKeyUsesSongTitleWhenReleaseTitleEmpty() {
        let playcut = Playcut.stub(releaseTitle: "")
        #expect(playcut.artworkCacheKey == "Juana Molina-la paradoja")
    }

    @Test("artworkCacheKey is consistent for same content")
    func artworkCacheKeyConsistentForSameContent() {
        let playcut1 = Playcut.stub(songTitle: "Song", artistName: "Artist", releaseTitle: "Album")
        let playcut2 = Playcut.stub(
            id: 2,
            hour: 2000,
            songTitle: "Song",
            labelName: "Different Label",
            artistName: "Artist",
            releaseTitle: "Album"
        )

        // Same artist and release should produce same cache key
        #expect(playcut1.artworkCacheKey == playcut2.artworkCacheKey)
    }

    @Test("artworkCacheKey differs for different artists")
    func artworkCacheKeyDiffersForDifferentArtists() {
        let playcut1 = Playcut.stub(songTitle: "Song", artistName: "Artist A", releaseTitle: "Album")
        let playcut2 = Playcut.stub(id: 2, songTitle: "Song", artistName: "Artist B", releaseTitle: "Album")

        #expect(playcut1.artworkCacheKey != playcut2.artworkCacheKey)
    }

    @Test("artworkCacheKey differs for different releases")
    func artworkCacheKeyDiffersForDifferentReleases() {
        let playcut1 = Playcut.stub(songTitle: "Song", artistName: "Artist", releaseTitle: "Album A")
        let playcut2 = Playcut.stub(id: 2, songTitle: "Song", artistName: "Artist", releaseTitle: "Album B")

        #expect(playcut1.artworkCacheKey != playcut2.artworkCacheKey)
    }

    // MARK: - HTML Entity Decoding Tests

    // MARK: - metadataStatus decoding (#270)

    @Test("Decodes inline metadataStatus from JSON", arguments: [
        ("pending", MetadataStatus.pending),
        ("enriching", MetadataStatus.enriching),
        ("enriched_match", MetadataStatus.enrichedMatch),
        ("enriched_no_match", MetadataStatus.enrichedNoMatch),
        ("failed_no_retry", MetadataStatus.failedNoRetry),
    ])
    func decodesMetadataStatusFromJSON(raw: String, expected: MetadataStatus) throws {
        let json = """
        {
            "id": 4242,
            "hour": 1000,
            "chronOrderID": 4242,
            "timeCreated": 1000,
            "songTitle": "la paradoja",
            "artistName": "Juana Molina",
            "releaseTitle": "DOGA",
            "labelName": "Sonamos",
            "rotation": false,
            "metadataStatus": "\(raw)"
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))
        #expect(playcut.metadataStatus == expected)
    }

    @Test("Decodes Playcut without metadataStatus field as nil (forward-compat)")
    func decodesPlaycutWithoutMetadataStatusAsNil() throws {
        let json = """
        {
            "id": 4243,
            "hour": 1000,
            "chronOrderID": 4243,
            "timeCreated": 1000,
            "songTitle": "Moon Pix",
            "artistName": "Cat Power",
            "releaseTitle": "Moon Pix",
            "labelName": "Matador Records",
            "rotation": false
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))
        #expect(playcut.metadataStatus == nil)
    }

    @Test("Decoder decodes HTML entities in string fields")
    func decoderDecodesHTMLEntities() throws {
        let json = """
        {
            "id": 123,
            "hour": 1000,
            "chronOrderID": 1,
            "timeCreated": 1000,
            "songTitle": "Test &#8217;Song&#8217;",
            "artistName": "Raphael Rogi&#324;ski &amp; Ruzi&#269;njak Tajni",
            "releaseTitle": "Test &lt;Album&gt;",
            "labelName": "Label &quot;Name&quot;",
            "rotation": "false"
        }
        """
        let data = Data(json.utf8)
        let playcut = try JSONDecoder().decode(Playcut.self, from: data)

        #expect(playcut.artistName == "Raphael Rogiński & Ruzičnjak Tajni")
        #expect(playcut.releaseTitle == "Test <Album>")
        #expect(playcut.songTitle == "Test \u{2019}Song\u{2019}")
        #expect(playcut.labelName == "Label \"Name\"")
    }
}
