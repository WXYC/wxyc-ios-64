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
import Concerts
import ConcertsTesting
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

    // MARK: - Genres/Styles Codable Tests (#402)

    @Test("Decoder reads inline genres and styles")
    func decoderReadsGenresAndStyles() throws {
        let json = """
        {
            "id": 402,
            "hour": 1000,
            "chronOrderID": 1,
            "timeCreated": 1000,
            "songTitle": "la paradoja",
            "artistName": "Juana Molina",
            "releaseTitle": "DOGA",
            "labelName": "Sonamos",
            "rotation": false,
            "genres": ["Rock"],
            "styles": ["Folk, World, & Country"]
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))

        #expect(playcut.genres == ["Rock"])
        #expect(playcut.styles == ["Folk, World, & Country"])
    }

    @Test("Genres and styles are nil when absent from the wire")
    func genresAndStylesNilWhenAbsent() throws {
        let json = """
        {
            "id": 403,
            "hour": 1000,
            "chronOrderID": 1,
            "timeCreated": 1000,
            "songTitle": "Call Your Name",
            "artistName": "Chuquimamani-Condori",
            "releaseTitle": "Edits",
            "rotation": false
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))

        #expect(playcut.genres == nil)
        #expect(playcut.styles == nil)
    }

    @Test("Genres and styles survive an encode/decode round-trip")
    func genresAndStylesRoundTrip() throws {
        let original = Playcut(
            id: 402,
            hour: 1000,
            chronOrderID: 402,
            timeCreated: 1000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            genres: ["Rock"],
            styles: ["Folk, World, & Country"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Playcut.self, from: data)

        #expect(decoded.genres == ["Rock"])
        #expect(decoded.styles == ["Folk, World, & Country"])
        #expect(decoded == original)
    }

    // MARK: - Embedded upcoming_show Tests (#473)

    @Test("Decoder reads the embedded upcoming_show concert off the feed")
    func decoderReadsUpcomingShow() throws {
        let json = """
        {
            "id": 473,
            "hour": 1000,
            "chronOrderID": 1,
            "timeCreated": 1000,
            "songTitle": "Back, Baby",
            "artistName": "Jessica Pratt",
            "releaseTitle": "On Your Own Love Again",
            "rotation": false,
            "upcoming_show": {
                "id": 4821,
                "venue": {
                    "id": 3,
                    "slug": "cats-cradle",
                    "name": "Cat's Cradle",
                    "city": "Carrboro",
                    "state": "NC",
                    "address": "300 E Main St"
                },
                "starts_on": "2026-08-01",
                "starts_at": "2026-08-02T00:00:00.000Z",
                "doors_at": "2026-08-01T23:00:00.000Z",
                "headlining_artist_raw": "Jessica Pratt",
                "headlining_artist_id": 512,
                "supporting_artists_raw": ["Julie Byrne"],
                "ticket_url": "https://www.etix.com/ticket/p/jessica-pratt",
                "price_min": 22,
                "price_max": 25,
                "age_restriction": "All Ages",
                "status": "on_sale"
            }
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))

        let show = try #require(playcut.upcomingShow)
        #expect(show.id == 4821)
        #expect(show.venue.name == "Cat's Cradle")
        #expect(show.headliningArtistRaw == "Jessica Pratt")
        #expect(show.status == .onSale)
        #expect(show.ctaURL == URL(string: "https://www.etix.com/ticket/p/jessica-pratt"))
    }

    @Test("upcomingShow is nil when absent from the wire")
    func upcomingShowNilWhenAbsent() throws {
        let json = """
        {
            "id": 474,
            "hour": 1000,
            "chronOrderID": 1,
            "timeCreated": 1000,
            "songTitle": "la paradoja",
            "artistName": "Juana Molina",
            "releaseTitle": "DOGA",
            "rotation": false
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))
        #expect(playcut.upcomingShow == nil)
    }

    @Test("An unknown upcoming_show status still decodes (tolerant)")
    func upcomingShowTolerantStatus() throws {
        let json = """
        {
            "id": 475,
            "hour": 1000,
            "chronOrderID": 1,
            "timeCreated": 1000,
            "songTitle": "Call Your Name",
            "artistName": "Chuquimamani-Condori",
            "releaseTitle": "Edits",
            "rotation": false,
            "upcoming_show": {
                "id": 99,
                "venue": {"id": 1, "slug": "v", "name": "Nightlight", "city": "Chapel Hill", "state": "NC"},
                "starts_on": "2026-08-01",
                "headlining_artist_raw": "Chuquimamani-Condori",
                "supporting_artists_raw": [],
                "status": "postponed_indefinitely"
            }
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))
        #expect(playcut.upcomingShow?.status == .unknown)
    }

    @Test("upcomingShow survives an encode/decode round-trip")
    func upcomingShowRoundTrip() throws {
        let original = Playcut.stub(
            id: 476,
            songTitle: "Back, Baby",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        ).withUpcomingShow(.stub(status: .soldOut))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Playcut.self, from: data)

        #expect(decoded.upcomingShow?.id == original.upcomingShow?.id)
        #expect(decoded.upcomingShow?.status == .soldOut)
        #expect(decoded == original)
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
