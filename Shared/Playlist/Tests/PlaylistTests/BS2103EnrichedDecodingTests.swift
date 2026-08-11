//
//  BS2103EnrichedDecodingTests.swift
//  Playlist
//
//  The iOS half of the Backend-Service#2103 wire contract: decodes the exact
//  bytes Backend-Service pins as its golden, plus every character class of URL
//  production actually serves on that feed.
//
//  Created by Jake Bromberg on 08/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CryptoKit
@testable import Playlist

/// BS#2103 enriches `GET /playlists/recentEntries?v=2` — the endpoint shipped
/// 3.2 binaries read through the `wxyc.info` proxy — with the metadata set those
/// binaries already know how to decode. Backend-side tests assert JSON key names
/// in JavaScript; none of them can observe what Swift does with the bytes.
///
/// The stakes are asymmetric, which is the whole reason this suite exists. All
/// eight URL-typed fields on ``Playcut`` decode through a *throwing*
/// `decodeIfPresent(URL.self, …)`, and ``Playlist/playcuts`` is a non-optional
/// array — so one malformed URL on one row fails the array decode, fails
/// `Playlist`, and blanks the playlist for that client until the row scrolls
/// off. The v2 flowsheet path is immune to the same data: `FlowsheetConverter`
/// converts with a non-throwing `URL(string:)`, and `Concert` goes out of its
/// way to do the same. `Playcut` never got that treatment, so on the v1 path the
/// server-side guard is the only line of defense.
///
/// ## Contract
///
/// `bs2103-enriched-payload.json` is a byte-identical copy of
/// `Backend-Service tests/fixtures/recent-entries-v2-wire-golden.json`, produced
/// by that repo's serializer. ``goldenSHA256`` is pinned in both repos. If the
/// backend regenerates its golden, this hash fails until the copy here is
/// refreshed — and refreshing it re-runs these expectations against the new
/// bytes, which is the point.
///
/// To refresh: copy the file from Backend-Service, run this suite, update
/// ``goldenSHA256`` in both places.
@Suite("BS#2103 enriched v1 payload decoding")
struct BS2103EnrichedDecodingTests {

    /// Pinned in `Backend-Service tests/unit/services/playlist-proxy-wire-golden.test.ts`
    /// as `GOLDEN_SHA256`. Must match.
    static let goldenSHA256 = "a789b99b863374b44ba2c8ca0c3393d9659987ff1e403e1be90834c500a49313"

    static func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "missing fixture \(name).\(ext)"
        )
    }

    static func loadPayload() throws -> Playlist {
        try JSONDecoder().decode(Playlist.self, from: Data(contentsOf: fixture("bs2103-enriched-payload", "json")))
    }

    static func playcut(_ playlist: Playlist, artist: String) throws -> Playcut {
        try #require(playlist.playcuts.first { $0.artistName == artist }, "no playcut for \(artist)")
    }

    // MARK: - The contract itself

    @Test("The fixture is the backend's pinned golden, byte for byte")
    func goldenHashMatches() throws {
        let data = try Data(contentsOf: Self.fixture("bs2103-enriched-payload", "json"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(
            digest == Self.goldenSHA256,
            """
            The golden changed. Confirm Backend-Service regenerated it deliberately, \
            re-read the expectations below against the new bytes, then update \
            goldenSHA256 here and GOLDEN_SHA256 in playlist-proxy-wire-golden.test.ts.
            """
        )
    }

    @Test("The enriched payload decodes as a Playlist")
    func payloadDecodes() throws {
        #expect(try Self.loadPayload().playcuts.count == 14)
    }

    // MARK: - Parser-differential and degenerate-array guards

    /// Probe 9013 persists values that WHATWG `new URL()` accepts while
    /// describing a *different* string than the backend would emit: a
    /// backslash-in-authority (`https://www.discogs.com\@evil.example/…`, which
    /// WHATWG folds to host `www.discogs.com` but Foundation resolves to host
    /// `evil.example`) and embedded tab / LF / space, which WHATWG strips or
    /// encodes before parsing. The backend now rejects these outright rather
    /// than emitting the unnormalized original.
    ///
    /// The asymmetry is the point: had a backslash value shipped, this decoder
    /// would have accepted it happily and opened the wrong host on tap — no
    /// throw, no signal, just a link to somewhere else.
    @Test("Values whose WHATWG parse disagrees with their bytes never arrive")
    func parserDifferentialsSuppressed() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "Hermanos Gutiérrez")

        #expect(playcut.discogsURL == nil) // backslash authority
        #expect(playcut.artistWikipediaURL == nil) // backslash authority
        #expect(playcut.spotifyURL == nil) // embedded tab
        #expect(playcut.youtubeMusicURL == nil) // embedded LF
        #expect(playcut.bandcampURL == nil) // embedded space
        // Narrow, not blunt: the clean sibling field on the same row survives.
        #expect(playcut.genres == ["Rock"])
    }

    /// Probe 9014 covers the one throwing decode that had no guard until now.
    /// `album_metadata.genres`/`styles` are `text[]` with nullable elements, so
    /// `[null]` is representable — and `decodeIfPresent([String].self)` throws
    /// on it exactly like a malformed URL, taking the whole playlist down. The
    /// backend now filters members and omits the key when nothing survives.
    @Test("Degenerate text[] members are filtered before they can throw")
    func degenerateArraysFiltered() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "Cat Power")

        // Persisted `['Rock', null, '', '  Folk Rock  ']` — nulls and blanks
        // dropped, survivors trimmed.
        #expect(playcut.genres == ["Rock", "Folk Rock"])
        // Persisted `[null]` — nothing survives, so the key is omitted entirely
        // rather than shipping an empty array.
        #expect(playcut.styles == nil)
        // Whitespace-only bio and empty note are dropped on the same rule.
        #expect(playcut.artistBio == nil)
        #expect(playcut.discogsUnavailableNote == nil)
        // The flag itself still rides — `true` is information, `''` was not.
        #expect(playcut.discogsUnavailable == true)
    }

    // MARK: - The happy path

    @Test("A fully-enriched playcut carries every metadata field")
    func fullyEnrichedPlaycut() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "Nilüfer Yanya")

        #expect(playcut.artworkURL?.absoluteString == "https://i.discogs.com/bs2103-painless.jpg")
        #expect(playcut.discogsURL?.absoluteString == "https://www.discogs.com/release/22012345")
        #expect(playcut.releaseYear == 2022)
        #expect(playcut.spotifyURL?.absoluteString == "https://open.spotify.com/album/1234567890abcdef")
        #expect(playcut.appleMusicURL?.absoluteString == "https://music.apple.com/us/album/painless/1609094304")
        #expect(playcut.youtubeMusicURL?.absoluteString == "https://music.youtube.com/playlist?list=OLAK5uy_bs2103")
        #expect(playcut.bandcampURL?.absoluteString == "https://niluferyanya.bandcamp.com/album/painless")
        #expect(playcut.soundcloudURL?.absoluteString == "https://soundcloud.com/niluferyanya/stabilise")
        #expect(playcut.artistBio == "Nilüfer Yanya is a London-born singer-songwriter.")
        #expect(playcut.genres == ["Rock"])
        #expect(playcut.styles == ["Indie Rock", "Art Rock"])
        #expect(playcut.artistId == 7000)
        #expect(playcut.metadataStatus == .enrichedMatch)
        #expect(playcut.discogsUnavailable == false)

        // The whole point of the change: this is what renders
        // `PlaycutMetadataSection` without an app update.
        #expect(playcut.hasV2Metadata)
    }

    /// The two deliberate snake_case exceptions. They round-trip through nested
    /// types with their own Codable, so a casing mistake here would be invisible
    /// to a key-name test on the backend but fatal to the feature.
    @Test("The snake_case embeds decode into their nested types")
    func snakeCaseEmbedsDecode() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "Nilüfer Yanya")

        let show = try #require(playcut.upcomingShow, "upcoming_show did not decode into a Concert")
        #expect(show.id == 991)
        #expect(show.headliningArtistRaw == "Nilüfer Yanya")
        #expect(show.venue.name == "Cat’s Cradle")
        #expect(show.ticketURL?.absoluteString == "https://catscradle.example/tickets/991")

        let reviews = try #require(playcut.criticReviews)
        #expect(reviews.count == 1)
    }

    @Test("A free-text play with no metadata decodes and stays un-enriched")
    func unenrichedPlaycut() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "BS2103 Unenriched Artist")

        #expect(playcut.artworkURL == nil)
        #expect(playcut.discogsURL == nil)
        #expect(playcut.spotifyURL == nil)
        #expect(playcut.artistBio == nil)
        #expect(playcut.genres == nil)
        #expect(playcut.artistId == nil)
        // Option-3 serve rule: with zero renderable inline fields the backend
        // withholds `metadataStatus` entirely (the column is `pending` in the
        // DB), so this decodes as nil — the same arm a pre-BS#2103 payload
        // takes — and the detail view issues its `/proxy/metadata/album` fetch.
        #expect(playcut.metadataStatus == nil)
        #expect(!playcut.hasV2Metadata)
    }

    // MARK: - Raw non-ASCII survives the wire

    /// The backend's guard returns the *trimmed original*, not a normalized
    /// `href`, so a value WHATWG accepts without rewriting reaches Swift
    /// verbatim. In production that is 21 distinct Wikipedia URLs carrying
    /// un-percent-encoded UTF-8 in the path — the riskiest class in the corpus,
    /// and the one worth naming rather than burying in the sweep.
    @Test(
        "Raw non-ASCII in a URL path decodes rather than throwing",
        arguments: [
            "João Gilberto",
            "İbrahim Tatlıses",
            "Konono Nº1",
            "Nilüfer Yanya",
        ]
    )
    func rawNonASCIIDecodes(artist: String) throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: artist)
        let wikipedia = try #require(playcut.artistWikipediaURL)
        // iOS 17+ defaults `URL(string:)` to `encodingInvalidCharacters: true`,
        // so the value is accepted and percent-encoded on the way in. Assert the
        // round trip, not byte identity.
        #expect(wikipedia.host() == "en.wikipedia.org")
        #expect(wikipedia.scheme == "http" || wikipedia.scheme == "https")
    }

    @Test("Apostrophes, parens and bangs in %-encoded search URLs decode")
    func apostropheSearchURLsDecode() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "Eiko Ishibashi & Jim O'Rourke")

        #expect(playcut.spotifyURL != nil)
        #expect(playcut.youtubeMusicURL != nil)
        #expect(playcut.soundcloudURL != nil)
        #expect(playcut.bandcampURL != nil)
    }

    // MARK: - The server-side guards, observed from the client

    /// Each of these rows has a persisted value the backend deliberately refuses
    /// to serialize. From here the only observable is a `nil` — which is exactly
    /// the contract: a dropped field costs one missing button, an emitted bad one
    /// costs the playlist.
    @Test(
        "Values the backend guard drops arrive as nil, not as a decode failure",
        arguments: [
            // Human-typed label prefix; 12 such rows in production.
            ("Hole", "artistWikipediaURL"),
            ("Art Garfunkel", "artistWikipediaURL"),
            // The '' synthetic-match sentinel (LML#401/#487, stripped by BS#1628).
            ("Jessica Pratt", "discogsURL"),
            // Bandcamp URL filed under spotify_url (BS#1714 host guard).
            ("Chuquimamani-Condori", "spotifyURL"),
        ]
    )
    func guardedFieldsArriveNil(artist: String, field: String) throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: artist)

        switch field {
        case "artistWikipediaURL": #expect(playcut.artistWikipediaURL == nil)
        case "discogsURL": #expect(playcut.discogsURL == nil)
        case "spotifyURL": #expect(playcut.spotifyURL == nil)
        default: Issue.record("unhandled field \(field)")
        }
    }

    @Test("A whitespace-padded URL is trimmed, a whitespace-only one is dropped")
    func whitespaceHandling() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "Juana Molina")

        #expect(playcut.discogsURL?.absoluteString == "https://www.discogs.com/release/999")
        #expect(playcut.artistWikipediaURL == nil)
    }

    @Test("Non-web schemes, scheme-relative refs, and bare hosts never reach the client")
    func nonWebSchemesDropped() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "Stereolab")

        #expect(playcut.discogsURL == nil) // javascript:alert(1)
        #expect(playcut.spotifyURL == nil) // //open.spotify.com/album/xyz
        #expect(playcut.bandcampURL == nil) // stereolab.bandcamp.com/... (no scheme)
    }

    /// The blank-card regression guard, and the reason `metadataStatus` is
    /// conditional on this endpoint. On shipped 3.2 a terminal status is a
    /// CONTROL field: `PlaycutDetailView.loadMetadata()` renders straight from
    /// the inline fields and never calls `/proxy/metadata/album` — and
    /// `hasV2Metadata` is true *because* the status is terminal, so a
    /// terminal-but-empty row builds an all-nil inline object and shows an
    /// empty card. Stereolab is exactly that row: `enriched_match` in the DB,
    /// every persisted value guarded off the wire. The backend therefore
    /// withholds the status (option-3 serve rule, measured at 579 of 37,054
    /// production playcuts), landing this row on the same fetch arm a
    /// pre-BS#2103 payload takes.
    @Test("A terminal-but-empty row arrives status-less and keeps the live-fetch fallback")
    func terminalButEmptyKeepsFallback() throws {
        let playcut = try Self.playcut(try Self.loadPayload(), artist: "Stereolab")

        // Status withheld → decodes nil → the `.pending/.enriching/nil` arm.
        #expect(playcut.metadataStatus == nil)
        // And the predicate that would have short-circuited the fetch is false.
        #expect(!playcut.hasV2Metadata)
        // Excluded-from-predicate fields still ride; they don't make the row
        // "renderable" and were never the blank-card hazard.
        #expect(playcut.artistId == 7000)
        #expect(playcut.discogsUnavailable == false)
    }

    // MARK: - The production corpus

    /// A durable subset of the URL values this feed actually serves, harvested
    /// from 251 pages of production `GET /flowsheet` (50,200 entries / 37,054
    /// playcut rows) on 2026-08-11 and filtered through the backend's `wireUrl`
    /// guard — i.e. the set that would reach this decoder once #2103 deploys.
    ///
    /// The one-off audit swept all 104,597 distinct values and found zero
    /// failures. What is checked in here is a 4,911-value reduction that keeps
    /// every value containing whitespace, non-ASCII, or an RFC-3986-unsafe
    /// character (1,321 of them), one representative of each of the 662 distinct
    /// hosts, and a deterministic sample of the rest. The redundant tail was
    /// mostly `open.spotify.com/search/…` strings and not worth 8 MB of history.
    ///
    /// This is a regression guard, not a proof about future data: a DJ can type a
    /// new malformed value tomorrow. What keeps *that* safe is the backend guard,
    /// which is why the counterfactual below matters as much as this sweep.
    ///
    /// All eight URL fields share one decode path, so each value is exercised
    /// once, in the field where production junk actually turned up.
    @Test("Every URL value production sends decodes without throwing")
    func productionCorpusDecodes() throws {
        let values = try String(contentsOf: Self.fixture("bs2103-prod-urls", "txt"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        // Guard against a silently-truncated fixture reading as a pass.
        #expect(values.count > 4_000, "corpus looks truncated: \(values.count) values")

        let decoder = JSONDecoder()
        var failures: [(String, String)] = []
        var decodedCount = 0

        for value in values {
            let data = try JSONSerialization.data(withJSONObject: Self.probe(wikipediaURL: value))
            do {
                if try decoder.decode(Playcut.self, from: data).artistWikipediaURL != nil { decodedCount += 1 }
            } catch {
                failures.append((value, "\(error)"))
            }
        }

        for (value, error) in failures.prefix(20) {
            Issue.record("decode failed for \(value.debugDescription): \(error)")
        }
        #expect(failures.isEmpty, "\(failures.count) of \(values.count) production values failed to decode")
        // Non-vacuity: a value that decoded to nil would pass the throw check
        // while silently dropping the link.
        #expect(decodedCount == values.count, "\(values.count - decodedCount) values decoded to nil")
    }

    /// The counterfactual that makes the backend guard load-bearing rather than
    /// decorative. Each of these four values is a real persisted
    /// `artist_wikipedia_url` — a human typed a label in front of the URL — and
    /// together they account for 12 production rows, most recently played
    /// 2026-08-11. #2103 refuses to serialize them; this is what happens if it
    /// stops.
    ///
    /// Measured, not assumed: all four throw `DecodingError.dataCorrupted`
    /// ("Invalid URL string"). Foundation does NOT degrade them to a relative
    /// URL. And because ``Playlist/playcuts`` is non-optional, the throw takes
    /// the whole playlist with it.
    @Test(
        "Each value the guard rejects would throw and blank the whole playlist",
        arguments: [
            "Wiki - http://en.wikipedia.org/wiki/Hole_(band)",
            "Wiki - https://en.wikipedia.org/wiki/Weezer",
            "Wiki - https://en.wikipedia.org/wiki/Monty_Python",
            "wikipedia : https://en.wikipedia.org/wiki/Art_Garfunkel",
        ]
    )
    func rejectedValuesWouldThrow(raw: String) throws {
        let probe = Self.probe(wikipediaURL: raw)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Playcut.self, from: JSONSerialization.data(withJSONObject: probe))
        }

        // And the blast radius: one bad row takes the array with it.
        let playlist: [String: Any] = ["playcuts": [probe], "talksets": [], "breakpoints": []]
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Playlist.self, from: JSONSerialization.data(withJSONObject: playlist))
        }
    }

    /// A minimal legal v1 playcut carrying one URL value under test.
    static func probe(wikipediaURL: String) -> [String: Any] {
        [
            "id": 1,
            "hour": 1_786_471_200_000,
            "chronOrderID": 1,
            "timeCreated": 1_786_471_201_000,
            "songTitle": "probe",
            "artistName": "probe",
            "rotation": "false",
            "artistWikipediaURL": wikipediaURL,
        ]
    }
}
