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

    @Test("A present-but-malformed upcoming_show (missing venue) degrades to nil, not a throw")
    func upcomingShowMalformedMissingVenueDegrades() throws {
        // The embed is present but drops the required `venue` sub-field — a
        // backend join regression. It must not fail the surrounding playcut decode.
        let json = """
        {
            "id": 477,
            "hour": 1000,
            "chronOrderID": 1,
            "timeCreated": 1000,
            "songTitle": "Call Your Name",
            "artistName": "Chuquimamani-Condori",
            "releaseTitle": "Edits",
            "rotation": false,
            "upcoming_show": {
                "id": 99,
                "starts_on": "2026-08-01",
                "headlining_artist_raw": "Chuquimamani-Condori",
                "supporting_artists_raw": [],
                "status": "on_sale"
            }
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))
        #expect(playcut.upcomingShow == nil)
        #expect(playcut.artistName == "Chuquimamani-Condori")
    }

    @Test("A present-but-malformed upcoming_show (bad starts_on) degrades to nil, not a throw")
    func upcomingShowMalformedBadDateDegrades() throws {
        // `starts_on` is not a well-formed yyyy-MM-dd string, which throws inside
        // `Concert.init(from:)`. The playcut around it must still decode.
        let json = """
        {
            "id": 478,
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
                "starts_on": "not-a-date",
                "headlining_artist_raw": "Chuquimamani-Condori",
                "supporting_artists_raw": [],
                "status": "on_sale"
            }
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))
        #expect(playcut.upcomingShow == nil)
        #expect(playcut.artistName == "Chuquimamani-Condori")
    }

    @Test("upcomingShow survives an encode/decode round-trip")
    func upcomingShowRoundTrip() throws {
        let original = Playcut.stub(
            id: 476,
            songTitle: "Back, Baby",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again",
            upcomingShow: .stub(status: .soldOut)
        )

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

// MARK: - artistId (BS#1625 / #492)

@Suite("Playcut artistId Tests")
struct PlaycutArtistIdTests {

    @Test("artistId decodes when present and is nil when absent")
    func decodesArtistId() throws {
        let json = """
        {
            "id": 1, "hour": 1706544000000, "chronOrderID": 1, "timeCreated": 1706549400000,
            "songTitle": "Back, Baby", "artistName": "Jessica Pratt", "artistId": 812
        }
        """
        let playcut = try JSONDecoder().decode(Playcut.self, from: Data(json.utf8))
        #expect(playcut.artistId == 812)

        let jsonAbsent = """
        {
            "id": 1, "hour": 1706544000000, "chronOrderID": 1, "timeCreated": 1706549400000,
            "songTitle": "Back, Baby", "artistName": "Jessica Pratt"
        }
        """
        let legacy = try JSONDecoder().decode(Playcut.self, from: Data(jsonAbsent.utf8))
        #expect(legacy.artistId == nil)
    }

    @Test("artistId survives an encode/decode round-trip (disk-cached playlists)")
    func artistIdRoundTrip() throws {
        let original = Playcut(
            id: 1,
            hour: 1706544000000,
            chronOrderID: 1,
            timeCreated: 1706549400000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            artistId: 645
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Playcut.self, from: data)
        #expect(decoded.artistId == 645)
    }
}

// MARK: - hasV2Metadata (#685)

/// Tests for `Playcut.hasV2Metadata`. The predicate must be the union of "any
/// of the 12 inline enriched fields is present" and "metadataStatus is
/// terminal" — a terminal row with zero enriched fields (canonical
/// failed_no_retry) still renders inline (base-only) rather than falling
/// through to the /proxy/metadata/album path.
@Suite("Playcut.hasV2Metadata Tests")
struct HasV2MetadataTests {

    private func playcut(
        artworkURL: URL? = nil,
        discogsURL: URL? = nil,
        releaseYear: Int? = nil,
        spotifyURL: URL? = nil,
        appleMusicURL: URL? = nil,
        youtubeMusicURL: URL? = nil,
        bandcampURL: URL? = nil,
        soundcloudURL: URL? = nil,
        artistBio: String? = nil,
        artistWikipediaURL: URL? = nil,
        genres: [String]? = nil,
        styles: [String]? = nil,
        artistId: Int? = nil,
        upcomingShow: Concert? = nil,
        criticReviews: [CriticReview]? = nil,
        metadataStatus: MetadataStatus? = nil
    ) -> Playcut {
        Playcut(
            id: 685,
            hour: 1000,
            chronOrderID: 685,
            timeCreated: 1000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            artworkURL: artworkURL,
            discogsURL: discogsURL,
            releaseYear: releaseYear,
            spotifyURL: spotifyURL,
            appleMusicURL: appleMusicURL,
            youtubeMusicURL: youtubeMusicURL,
            bandcampURL: bandcampURL,
            soundcloudURL: soundcloudURL,
            artistBio: artistBio,
            artistWikipediaURL: artistWikipediaURL,
            genres: genres,
            styles: styles,
            artistId: artistId,
            upcomingShow: upcomingShow,
            criticReviews: criticReviews,
            metadataStatus: metadataStatus
        )
    }

    // MARK: - Any-field-alone (non-terminal / nil status)

    @Test("nil status, no inline fields is false")
    func nilStatusNoFieldsIsFalse() {
        #expect(playcut().hasV2Metadata == false)
    }

    @Test(
        "nil status, exactly one of the 12 inline fields is true",
        arguments: [
            "artworkURL", "discogsURL", "releaseYear", "spotifyURL", "appleMusicURL",
            "youtubeMusicURL", "bandcampURL", "soundcloudURL", "artistBio",
            "artistWikipediaURL", "genres", "styles",
        ]
    )
    func nilStatusSingleFieldIsTrue(field: String) {
        let url = URL(string: "https://example.com")!
        let p: Playcut
        switch field {
        case "artworkURL": p = playcut(artworkURL: url)
        case "discogsURL": p = playcut(discogsURL: url)
        case "releaseYear": p = playcut(releaseYear: 2022)
        case "spotifyURL": p = playcut(spotifyURL: url)
        case "appleMusicURL": p = playcut(appleMusicURL: url)
        case "youtubeMusicURL": p = playcut(youtubeMusicURL: url)
        case "bandcampURL": p = playcut(bandcampURL: url)
        case "soundcloudURL": p = playcut(soundcloudURL: url)
        case "artistBio": p = playcut(artistBio: "Argentine singer-songwriter.")
        case "artistWikipediaURL": p = playcut(artistWikipediaURL: url)
        case "genres": p = playcut(genres: ["Rock"])
        case "styles": p = playcut(styles: ["Folk, World, & Country"])
        default: fatalError("unhandled field \(field)")
        }
        #expect(p.hasV2Metadata == true)
    }

    @Test("nil status, empty (non-nil) genres/styles arrays are false")
    func nilStatusEmptyArraysAreFalse() {
        #expect(playcut(genres: []).hasV2Metadata == false)
        #expect(playcut(styles: []).hasV2Metadata == false)
    }

    // MARK: - Terminal-alone (zero enriched fields)

    @Test(
        "terminal status with zero enriched fields is true",
        arguments: [MetadataStatus.enrichedMatch, .enrichedNoMatch, .failedNoRetry]
    )
    func terminalStatusZeroFieldsIsTrue(status: MetadataStatus) {
        #expect(playcut(metadataStatus: status).hasV2Metadata == true)
    }

    // MARK: - Non-terminal status regression (pending/enriching with no fields)

    @Test(
        "non-terminal status with zero enriched fields is false",
        arguments: [MetadataStatus.pending, .enriching]
    )
    func nonTerminalStatusZeroFieldsIsFalse(status: MetadataStatus) {
        #expect(playcut(metadataStatus: status).hasV2Metadata == false)
    }

    // MARK: - Union: terminal status + sparse fields still true

    @Test("terminal status with a single non-streaming field (genres only) is true")
    func terminalStatusGenresOnlyIsTrue() {
        #expect(playcut(genres: ["Rock"], metadataStatus: .failedNoRetry).hasV2Metadata == true)
    }

    // MARK: - Excluded fields (artistId, upcomingShow, criticReviews — #695)

    /// `artistId`, `upcomingShow`, and `criticReviews` are real, additive
    /// inline fields — decoded onto `Playcut` and (for `criticReviews`) also
    /// folded into the `PlaycutDetailView` inline builder — but none of them
    /// is part of the 12-field predicate. Each is gated by its own
    /// independent mechanism instead: `artistId` by the likes feature,
    /// `upcomingShow` by the Box Office CTA, and `criticReviews` by
    /// `AlbumMetadata.hasCriticReviews` / `CriticReviewsFeature.shouldShowReviews`.
    @Test(
        "nil status, exactly one excluded field alone is still false",
        arguments: ["artistId", "upcomingShow", "criticReviews"]
    )
    func excludedFieldAloneIsFalse(field: String) {
        let p: Playcut
        switch field {
        case "artistId":
            p = playcut(artistId: 812)
        case "upcomingShow":
            p = playcut(upcomingShow: .stub())
        case "criticReviews":
            let review = CriticReview(
                source: "The Quietus",
                url: URL(string: "https://thequietus.com/a/1")!,
                snippet: "Great."
            )
            p = playcut(criticReviews: [review])
        default:
            fatalError("unhandled field \(field)")
        }
        #expect(p.hasV2Metadata == false)
    }

    @Test("terminal status with only criticReviews (no other inline fields) is still true — the terminal-status arm, not the field")
    func terminalStatusCriticReviewsOnlyIsTrueViaTerminalArm() {
        let review = CriticReview(
            source: "The Quietus",
            url: URL(string: "https://thequietus.com/a/1")!,
            snippet: "Great."
        )
        // True here comes from `metadataStatus.isTerminal`, not from
        // `criticReviews` — proven by `excludedFieldAloneIsFalse` above, which
        // holds `metadataStatus` nil and shows criticReviews alone is false.
        #expect(playcut(criticReviews: [review], metadataStatus: .failedNoRetry).hasV2Metadata == true)
    }
}
