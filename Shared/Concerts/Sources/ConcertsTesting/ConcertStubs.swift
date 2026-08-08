//
//  ConcertStubs.swift
//  ConcertsTesting
//
//  Convenience stub factories for `Concert` and `Venue`. Defaults use a
//  WXYC-canonical touring artist (Jessica Pratt at Cat's Cradle) rather than
//  placeholder strings. See `docs/test-fixtures.md` for the example pool.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Concerts

extension Venue {
    /// Creates a `Venue` with sensible defaults for testing (Cat's Cradle).
    ///
    /// Defaults read from ``Venue/catsCradle`` in `Concerts` rather than
    /// restating the literal, so the stub venue and the app-preview venue can
    /// never disagree (#771).
    public static func stub(
        id: Int = Venue.catsCradle.id,
        slug: String = Venue.catsCradle.slug,
        name: String = Venue.catsCradle.name,
        city: String = Venue.catsCradle.city,
        state: String = Venue.catsCradle.state,
        address: String? = Venue.catsCradle.address
    ) -> Venue {
        Venue(id: id, slug: slug, name: name, city: city, state: state, address: address)
    }
}

extension Concert {
    /// A fixed, deterministic default `starts_on` (2026-08-01, station zone) for
    /// stubs.
    ///
    /// The test-facing spelling of ``Concert/fixtureStartsOn``, which `Concerts`
    /// owns. Kept as its own name because ~100 call sites read `defaultStartsOn`
    /// and the two vocabularies (stub / fixture) are worth keeping legible.
    public static var defaultStartsOn: Date { fixtureStartsOn }

    /// Builds an instant on the default `starts_on` day at a station-zone
    /// wall-clock `hour`/`minute` — the ergonomic replacement for the old
    /// `HH:mm:ss` time strings. Returns `nil` for `nil` input so a caller can
    /// express "no doors/show time".
    ///
    /// Forwards to ``Concert/fixtureInstant(hour:minute:)``.
    public static func stubInstant(hour: Int?, minute: Int = 0) -> Date? {
        fixtureInstant(hour: hour, minute: minute)
    }

    /// Creates a `Concert` with sensible defaults for testing.
    ///
    /// Times default to 7 PM doors / 8 PM show (station zone). Pass
    /// `doorsAt: nil` / `startsAt: nil` for a date-only concert. Use
    /// ``stubInstant(hour:minute:)`` to build other wall-clock times.
    ///
    /// `id` and `ticketURL` read from `Concerts`' fixture literals rather than
    /// restating them, so the stub and the app-preview fixture can never
    /// disagree. `eventURL` deliberately stays `nil` — see
    /// ``Concert/fixtureEventURL``.
    public static func stub(
        id: Int = Concert.fixtureId,
        venue: Venue = .stub(),
        startsOn: Date? = nil,
        startsAt: Date? = Concert.stubInstant(hour: 20),
        doorsAt: Date? = Concert.stubInstant(hour: 19),
        headliningArtistRaw: String = "Jessica Pratt",
        headliningArtistId: Int? = 512,
        title: String? = nil,
        supportingArtistsRaw: [String] = ["Julie Byrne"],
        ticketURL: URL? = Concert.fixtureTicketURL,
        imageURL: URL? = nil,
        eventURL: URL? = nil,
        priceMin: Double? = 22.0,
        priceMax: Double? = 25.0,
        ageRestriction: String? = "All Ages",
        status: ShowStatus = .onSale,
        genres: [String]? = nil,
        similarArtists: [SimilarArtist]? = nil,
        stationPlays: Int? = nil,
        stationRecommended: Bool = false,
        stationRecommendedRank: Int? = nil,
        artistBio: String? = nil
    ) -> Concert {
        Concert(
            id: id,
            venue: venue,
            startsOn: startsOn ?? defaultStartsOn,
            startsAt: startsAt,
            doorsAt: doorsAt,
            headliningArtistRaw: headliningArtistRaw,
            headliningArtistId: headliningArtistId,
            title: title,
            supportingArtistsRaw: supportingArtistsRaw,
            ticketURL: ticketURL,
            imageURL: imageURL,
            eventURL: eventURL,
            priceMin: priceMin,
            priceMax: priceMax,
            ageRestriction: ageRestriction,
            status: status,
            genres: genres,
            similarArtists: similarArtists,
            stationPlays: stationPlays,
            stationRecommended: stationRecommended,
            stationRecommendedRank: stationRecommendedRank,
            artistBio: artistBio
        )
    }
}
