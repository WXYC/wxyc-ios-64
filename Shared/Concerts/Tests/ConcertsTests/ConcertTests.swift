//
//  ConcertTests.swift
//  Concerts
//
//  Decode + intrinsic-accessor tests for the concert model. The wire shape is
//  Backend-Service's `Concert`/`Venue` schema (`wxyc-shared/api.yaml`).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

@Suite("Concert")
struct ConcertTests {

    /// A realistic full-detail concert payload (Jessica Pratt at Cat's Cradle),
    /// using a WXYC-canonical touring artist and the backend `Concert` shape.
    private static let fullJSON = """
    {
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
        "title": null,
        "supporting_artists_raw": ["Julie Byrne"],
        "ticket_url": "https://www.etix.com/ticket/p/jessica-pratt",
        "image_url": "https://img.example/jessica-pratt.jpg",
        "event_url": "https://catscradle.com/event/jessica-pratt",
        "price_min": 22.0,
        "price_max": 25.0,
        "age_restriction": "All Ages",
        "genres": ["Rock", "Folk World & Country"],
        "station_plays": 137,
        "station_recommended": true,
        "status": "on_sale"
    }
    """

    // MARK: - Full decode

    @Test("Decodes a full concert payload")
    func decodesFullPayload() throws {
        let concert = try JSONDecoder().decode(Concert.self, from: Data(Self.fullJSON.utf8))

        #expect(concert.id == 4821)
        #expect(concert.venue.id == 3)
        #expect(concert.venue.slug == "cats-cradle")
        #expect(concert.venue.name == "Cat's Cradle")
        #expect(concert.venue.city == "Carrboro")
        #expect(concert.venue.state == "NC")
        #expect(concert.venue.address == "300 E Main St")
        #expect(concert.headliningArtistRaw == "Jessica Pratt")
        #expect(concert.headliningArtistId == 512)
        #expect(concert.title == nil)
        #expect(concert.supportingArtistsRaw == ["Julie Byrne"])
        #expect(concert.status == .onSale)
        #expect(concert.priceMin == 22.0)
        #expect(concert.priceMax == 25.0)
        #expect(concert.ticketURL == URL(string: "https://www.etix.com/ticket/p/jessica-pratt"))
        #expect(concert.imageURL == URL(string: "https://img.example/jessica-pratt.jpg"))
        #expect(concert.eventURL == URL(string: "https://catscradle.com/event/jessica-pratt"))
        #expect(concert.ageRestriction == "All Ages")
        #expect(concert.genres == ["Rock", "Folk World & Country"])
        #expect(concert.stationPlays == 137)
        #expect(concert.stationRecommended == true)
    }

    @Test("Parses starts_on as a calendar day in the station's time zone")
    func parsesDateInStationZone() throws {
        let concert = try JSONDecoder().decode(Concert.self, from: Data(Self.fullJSON.utf8))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: concert.startsOn)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 1)
    }

    @Test("Parses the starts_at / doors_at instants as venue wall-clock times")
    func parsesInstants() throws {
        let concert = try JSONDecoder().decode(Concert.self, from: Data(Self.fullJSON.utf8))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt

        // 2026-08-02T00:00:00Z is 8 PM Eastern on 2026-08-01 (EDT, UTC-4).
        let showHour = calendar.component(.hour, from: try #require(concert.startsAt))
        #expect(showHour == 20)
        // 2026-08-01T23:00:00Z is 7 PM Eastern.
        let doorsHour = calendar.component(.hour, from: try #require(concert.doorsAt))
        #expect(doorsHour == 19)
    }

    // MARK: - Minimal / degraded decode

    @Test("Decodes a minimal date-only payload, leaving optionals nil")
    func decodesMinimalPayload() throws {
        let json = """
        {
            "id": 12,
            "venue": {
                "id": 1,
                "slug": "local-506",
                "name": "Local 506",
                "city": "Chapel Hill",
                "state": "NC",
                "address": null
            },
            "starts_on": "2026-09-15",
            "starts_at": null,
            "doors_at": null,
            "headlining_artist_raw": "Chuquimamani-Condori",
            "headlining_artist_id": null,
            "title": null,
            "supporting_artists_raw": [],
            "ticket_url": null,
            "image_url": null,
            "event_url": null,
            "price_min": null,
            "price_max": null,
            "age_restriction": null,
            "status": "sold_out"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))

        #expect(concert.id == 12)
        #expect(concert.venue.name == "Local 506")
        #expect(concert.venue.address == nil)
        #expect(concert.headliningArtistRaw == "Chuquimamani-Condori")
        #expect(concert.status == .soldOut)
        #expect(concert.headliningArtistId == nil)
        #expect(concert.title == nil)
        #expect(concert.supportingArtistsRaw == [])
        #expect(concert.startsAt == nil)
        #expect(concert.doorsAt == nil)
        #expect(concert.priceMin == nil)
        #expect(concert.priceMax == nil)
        #expect(concert.ticketURL == nil)
        #expect(concert.imageURL == nil)
        #expect(concert.eventURL == nil)
        #expect(concert.ageRestriction == nil)
        #expect(concert.genres == nil)
        #expect(concert.similarArtists == nil)
        #expect(concert.stationPlays == nil)
        #expect(concert.stationRecommended == false)
    }

    @Test("Coalesces an absent supporting_artists_raw to an empty array")
    func coalescesAbsentSupportingArtists() throws {
        let json = """
        {
            "id": 7,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.supportingArtistsRaw == [])
    }

    @Test("Decodes an empty-string ticket_url to a nil ticketURL without throwing")
    func decodesEmptyTicketURLAsNil() throws {
        // The backend stores an unknown link as "" verbatim; a strict
        // URL(from:) decode would throw DecodingError.dataCorrupted here.
        let json = """
        {
            "id": 3,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "ticket_url": "",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.ticketURL == nil)
        #expect(concert.ctaURL == nil)
    }

    @Test("Decodes a malformed image_url to a nil imageURL without throwing")
    func decodesMalformedImageURLAsNil() throws {
        let json = """
        {
            "id": 4,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "image_url": "http://  ",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.imageURL == nil)
    }

    @Test("Decodes an unrecognized status as .unknown without throwing")
    func decodesUnknownStatus() throws {
        let json = """
        {
            "id": 1,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "status": "postponed"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.status == .unknown)
    }

    // MARK: - Genres (R2, forward-compatible optional)

    @Test("Decodes an explicit-null genres to nil without throwing")
    func decodesNullGenresAsNil() throws {
        // The backend emits `genres: null` for an unresolved headliner or before
        // the nightly enrichment has run — the same null-when-absent discipline as
        // the flowsheet `genres`/`styles` fields.
        let json = """
        {
            "id": 88,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "genres": null,
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.genres == nil)
    }

    @Test("Decodes a present genres array, preserving order")
    func decodesPresentGenres() throws {
        let json = """
        {
            "id": 89,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Chuquimamani-Condori",
            "genres": ["Electronic", "Latin"],
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.genres == ["Electronic", "Latin"])
    }

    @Test("Round-trips genres through encode/decode")
    func roundTripsGenres() throws {
        let original = Concert.stub(genres: ["Rock", "Jazz"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Concert.self, from: data)
        #expect(decoded.genres == ["Rock", "Jazz"])
    }

    // MARK: - event_url (#540, forward-compatible optional)

    @Test("Decodes an absent event_url to nil (backend not yet emitting)")
    func decodesAbsentEventURLAsNil() throws {
        let json = """
        {
            "id": 90,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.eventURL == nil)
    }

    @Test("Decodes an empty-string event_url to a nil eventURL without throwing")
    func decodesEmptyEventURLAsNil() throws {
        let json = """
        {
            "id": 91,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "event_url": "",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.eventURL == nil)
    }

    @Test("Decodes a malformed event_url to a nil eventURL without throwing")
    func decodesMalformedEventURLAsNil() throws {
        let json = """
        {
            "id": 92,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "event_url": "http://  ",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.eventURL == nil)
    }

    @Test("Round-trips event_url through encode/decode")
    func roundTripsEventURL() throws {
        let original = Concert.stub(eventURL: URL(string: "https://catscradle.com/event/jessica-pratt"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Concert.self, from: data)
        #expect(decoded.eventURL == URL(string: "https://catscradle.com/event/jessica-pratt"))
    }

    // MARK: - Similar artists (R3b For You, forward-compatible optional)

    @Test("Decodes a present similar_artists array, preserving order")
    func decodesPresentSimilarArtists() throws {
        let json = """
        {
            "id": 93,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Stereolab",
            "similar_artists": [
                { "artist_id": 41, "weight": 0.92 },
                { "artist_id": 77, "weight": 0.5 }
            ],
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.similarArtists == [
            SimilarArtist(artistId: 41, weight: 0.92),
            SimilarArtist(artistId: 77, weight: 0.5),
        ])
    }

    @Test("Decodes an explicit-null similar_artists to nil without throwing")
    func decodesNullSimilarArtistsAsNil() throws {
        // The backend emits `similar_artists: null` for an unresolved headliner or
        // before the nightly enrichment has run — the same null-when-absent
        // discipline as `genres`.
        let json = """
        {
            "id": 94,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "similar_artists": null,
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.similarArtists == nil)
    }

    @Test("Decodes an absent similar_artists to nil (backend not yet emitting)")
    func decodesAbsentSimilarArtistsAsNil() throws {
        let json = """
        {
            "id": 95,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.similarArtists == nil)
    }

    @Test("Round-trips similar_artists through encode/decode")
    func roundTripsSimilarArtists() throws {
        let original = Concert.stub(similarArtists: [
            SimilarArtist(artistId: 41, weight: 0.92),
            SimilarArtist(artistId: 77, weight: 0.5),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Concert.self, from: data)
        #expect(decoded.similarArtists == [
            SimilarArtist(artistId: 41, weight: 0.92),
            SimilarArtist(artistId: 77, weight: 0.5),
        ])
    }

    @Test("Drops malformed similar_artists elements instead of failing the whole page decode")
    func dropsMalformedSimilarArtistElements() throws {
        // One well-formed neighbor plus a missing-weight object and a wrong-typed
        // weight. Per the same one-bad-row-can't-break-the-page discipline as the
        // URL fields, the bad elements are dropped and the good one survives —
        // rather than throwing and blanking the entire GET /concerts page.
        let json = """
        {
            "id": 96,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Stereolab",
            "similar_artists": [
                { "artist_id": 41, "weight": 0.92 },
                { "artist_id": 77 },
                { "artist_id": 88, "weight": "high" }
            ],
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.similarArtists == [SimilarArtist(artistId: 41, weight: 0.92)])
    }

    @Test("A similar_artists array whose elements are all malformed decodes to an empty array")
    func allMalformedSimilarArtistsDecodesToEmpty() throws {
        // The field is present (so not nil) but nothing in it is usable → []. The
        // For You engine treats [] and nil identically, so this is a safe degrade.
        let json = """
        {
            "id": 97,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Stereolab",
            "similar_artists": [ { "artist_id": 77 } ],
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.similarArtists == [])
    }

    // MARK: - Station plays (#549, forward-compatible optional)

    @Test("Decodes a present station_plays to stationPlays")
    func decodesPresentStationPlays() throws {
        let json = """
        {
            "id": 200,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Deerhoof",
            "station_plays": 137,
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.stationPlays == 137)
    }

    @Test("Decodes an explicit-null station_plays to nil without throwing")
    func decodesNullStationPlaysAsNil() throws {
        // The backend emits `station_plays: null` for an unresolved headliner or an
        // artist with no play count — the same null-when-absent discipline as
        // `similar_artists`.
        let json = """
        {
            "id": 201,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "station_plays": null,
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.stationPlays == nil)
    }

    @Test("Decodes an absent station_plays to nil (backend not yet emitting)")
    func decodesAbsentStationPlaysAsNil() throws {
        let json = """
        {
            "id": 202,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.stationPlays == nil)
    }

    @Test("Round-trips station_plays through encode/decode")
    func roundTripsStationPlays() throws {
        let original = Concert.stub(stationPlays: 137)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Concert.self, from: data)
        #expect(decoded.stationPlays == 137)
    }

    // MARK: - Station recommended (#577, forward-compatible with a false default)

    @Test("Decodes a present station_recommended to stationRecommended")
    func decodesPresentStationRecommended() throws {
        let json = """
        {
            "id": 210,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Deerhoof",
            "station_recommended": true,
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.stationRecommended == true)
    }

    @Test("Decodes an explicit-false station_recommended to false")
    func decodesFalseStationRecommended() throws {
        let json = """
        {
            "id": 211,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "station_recommended": false,
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.stationRecommended == false)
    }

    @Test("Decodes an explicit-null station_recommended to false without throwing")
    func decodesNullStationRecommendedAsFalse() throws {
        // The same null-tolerant discipline as `station_plays`: a null from an
        // in-between backend build degrades to "not recommended", never a throw.
        let json = """
        {
            "id": 212,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "station_recommended": null,
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.stationRecommended == false)
    }

    @Test("Decodes an absent station_recommended to false (backend not yet emitting)")
    func decodesAbsentStationRecommendedAsFalse() throws {
        let json = """
        {
            "id": 213,
            "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
            "starts_on": "2026-08-20",
            "headlining_artist_raw": "Juana Molina",
            "status": "on_sale"
        }
        """
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.stationRecommended == false)
    }

    @Test("Round-trips station_recommended through encode/decode")
    func roundTripsStationRecommended() throws {
        let original = Concert.stub(stationRecommended: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Concert.self, from: data)
        #expect(decoded.stationRecommended == true)
    }

    // MARK: - ctaURL / headlineName (intrinsic data selection)

    @Test("ctaURL prefers the venue event page over the ticket link")
    func ctaURLPrefersEventPage() {
        let concert = Concert.stub(
            ticketURL: URL(string: "https://etix.com/x"),
            eventURL: URL(string: "https://catscradle.com/event/x")
        )
        #expect(concert.ctaURL == URL(string: "https://catscradle.com/event/x"))
    }

    @Test("ctaURL falls back to the ticket link when no venue page is known")
    func ctaURLFallsBackToTicketURL() {
        let concert = Concert.stub(ticketURL: URL(string: "https://etix.com/x"), eventURL: nil)
        #expect(concert.ctaURL == URL(string: "https://etix.com/x"))
    }

    @Test("ctaURL is nil when the concert carries no link at all")
    func ctaURLNilWhenNoLink() {
        let concert = Concert.stub(ticketURL: nil, eventURL: nil)
        #expect(concert.ctaURL == nil)
    }

    @Test("headlineName prefers the event title over the billed headliner")
    func headlineNamePrefersTitle() {
        let titled = Concert.stub(headliningArtistRaw: "Jessica Pratt", title: "An Evening With Jessica Pratt")
        #expect(titled.headlineName == "An Evening With Jessica Pratt")
        let untitled = Concert.stub(headliningArtistRaw: "Jessica Pratt", title: nil)
        #expect(untitled.headlineName == "Jessica Pratt")
    }

    // MARK: - shareURL (#536 — the canonical public share link)

    @Test("shareURL is the canonical wxyc.org/shows/<id> link")
    func shareURLIsCanonical() {
        let concert = Concert.stub(id: 4821)
        #expect(concert.shareURL == URL(string: "https://wxyc.org/shows/4821"))
    }

    @Test("shareURL carries the concert id, so distinct shows share distinct links")
    func shareURLRoundTripsID() {
        #expect(Concert.stub(id: 17).shareURL == URL(string: "https://wxyc.org/shows/17"))
        #expect(Concert.stub(id: 90210).shareURL == URL(string: "https://wxyc.org/shows/90210"))
        #expect(Concert.stub(id: 1).shareURL != Concert.stub(id: 2).shareURL)
    }
}
