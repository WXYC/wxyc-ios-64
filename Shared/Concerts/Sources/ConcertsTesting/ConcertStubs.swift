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

import Foundation
import Concerts

extension Venue {
    /// Creates a `Venue` with sensible defaults for testing (Cat's Cradle).
    public static func stub(
        id: Int = 3,
        slug: String = "cats-cradle",
        name: String = "Cat's Cradle",
        city: String = "Carrboro",
        state: String = "NC",
        address: String? = "300 E Main St"
    ) -> Venue {
        Venue(id: id, slug: slug, name: name, city: city, state: state, address: address)
    }
}

extension Concert {
    /// The station (venue) time zone, mirrored here so the stub helpers can build
    /// deterministic wall-clock instants without reaching into the `Concerts`
    /// module's internal `TimeZone.wxycStation`.
    private static let stationTimeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    /// A fixed, deterministic default `starts_on` (2026-08-01, station zone) for
    /// stubs. Falls back to a fixed epoch offset so the helper stays
    /// force-unwrap-free.
    public static let defaultStartsOn: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stationTimeZone
        let components = DateComponents(year: 2026, month: 8, day: 1)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_785_898_800)
    }()

    /// Builds an instant on the default `starts_on` day at a station-zone
    /// wall-clock `hour`/`minute` — the ergonomic replacement for the old
    /// `HH:mm:ss` time strings. Returns `nil` for `nil` input so a caller can
    /// express "no doors/show time".
    public static func stubInstant(hour: Int?, minute: Int = 0) -> Date? {
        guard let hour else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stationTimeZone
        var components = calendar.dateComponents([.year, .month, .day], from: defaultStartsOn)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// Creates a `Concert` with sensible defaults for testing.
    ///
    /// Times default to 7 PM doors / 8 PM show (station zone). Pass
    /// `doorsAt: nil` / `startsAt: nil` for a date-only concert. Use
    /// ``stubInstant(hour:minute:)`` to build other wall-clock times.
    public static func stub(
        id: Int = 4821,
        venue: Venue = .stub(),
        startsOn: Date? = nil,
        startsAt: Date? = Concert.stubInstant(hour: 20),
        doorsAt: Date? = Concert.stubInstant(hour: 19),
        headliningArtistRaw: String = "Jessica Pratt",
        headliningArtistId: Int? = 512,
        title: String? = nil,
        supportingArtistsRaw: [String] = ["Julie Byrne"],
        ticketURL: URL? = URL(string: "https://www.etix.com/ticket/p/jessica-pratt"),
        imageURL: URL? = nil,
        eventURL: URL? = nil,
        priceMin: Double? = 22.0,
        priceMax: Double? = 25.0,
        ageRestriction: String? = "All Ages",
        status: ShowStatus = .onSale,
        genres: [String]? = nil,
        similarArtists: [SimilarArtist]? = nil,
        stationPlays: Int? = nil
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
            stationPlays: stationPlays
        )
    }
}
