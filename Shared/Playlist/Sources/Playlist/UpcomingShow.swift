//
//  UpcomingShow.swift
//  Playlist
//
//  A touring-band show surfaced on a playcut when the played artist has an
//  upcoming Triangle-area date. The wire shape mirrors triangle-shows'
//  `EventResponse` (WXYC/triangle-shows backend/app/schemas.py); the eventual
//  iOS source is Backend-Service's concerts pipeline, which carries these fields
//  through (see triangle-shows-integration-proposal.md).
//
//  Placed in the `Playlist` package alongside `Playcut` — an upcoming show is an
//  enrichment on a played track, the same role `artistBio`/streaming links play.
//  See ``ShowStatus`` for the rationale and the promotion path to a shared
//  `Concerts` package if the standalone "Touring Soon" tab is built.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// An upcoming touring-band show, as rendered by the Box Office ticket.
///
/// Decoding is deliberately tolerant: only `id`, `name`, `date`, and `status`
/// are required, every other field is optional, and an unrecognized `status`
/// degrades to ``ShowStatus/unknown``. A partially-populated event (a common
/// case — many scraped listings are date-only with no price or times) still
/// decodes and renders, degrading gracefully rather than throwing.
public struct UpcomingShow: Codable, Sendable, Equatable, Hashable, Identifiable {

    /// Source event id (triangle-shows `events.id`). Stable per event.
    public let id: Int

    /// The event's own title (`Event.name`), which can differ from ``artist``
    /// (e.g. a festival or a billed night). Always present.
    public let eventName: String

    /// The headlining artist, when the source distinguishes it from the event
    /// name. This is the field matched against the playcut's artist.
    public let artist: String?

    /// Supporting acts, as a single source-formatted string (e.g. "Julie Byrne").
    public let supportArtists: String?

    /// Denormalized venue name (e.g. "Cat's Cradle"). Optional on the wire.
    public let venueName: String?

    /// Denormalized venue city (e.g. "Carrboro").
    public let venueCity: String?

    /// Denormalized venue accent color as a hex string (e.g. "#B34876"), used to
    /// tint the ticket glow. Optional.
    public let venueColorHex: String?

    /// The calendar day of the show, anchored to the station's time zone
    /// (US Eastern). Parsed from a date-only `yyyy-MM-dd` wire value.
    public let date: Date

    /// Doors time as the raw `HH:mm:ss` wire string, or `nil`. Kept as a string
    /// (not a `Date`) because many listings are date-only; the presenter formats it.
    public let doorsTime: String?

    /// Set/show time as the raw `HH:mm:ss` wire string, or `nil`.
    public let showTime: String?

    /// Ticket-availability state. Drives the pill and CTA wording.
    public let status: ShowStatus

    /// Lowest advertised price in dollars, or `nil` when unpriced/unknown.
    public let priceMin: Double?

    /// Highest advertised price in dollars, or `nil`.
    public let priceMax: Double?

    /// Direct ticketing link (`Event.ticket_url`), often a third-party seller.
    /// Frequently absent; ``ctaURL`` falls back to it after ``sourceURL``.
    public let ticketURL: URL?

    /// The venue's own event page (`Event.source_url`) — the preferred CTA
    /// target, since it is the reliable, first-party page for the show.
    public let sourceURL: URL?

    /// Event/promo image, or `nil`.
    public let imageURL: URL?

    /// Age policy string as advertised (e.g. "All Ages", "18+"), or `nil`.
    public let ageRestriction: String?

    public init(
        id: Int,
        eventName: String,
        artist: String? = nil,
        supportArtists: String? = nil,
        venueName: String? = nil,
        venueCity: String? = nil,
        venueColorHex: String? = nil,
        date: Date,
        doorsTime: String? = nil,
        showTime: String? = nil,
        status: ShowStatus,
        priceMin: Double? = nil,
        priceMax: Double? = nil,
        ticketURL: URL? = nil,
        sourceURL: URL? = nil,
        imageURL: URL? = nil,
        ageRestriction: String? = nil
    ) {
        self.id = id
        self.eventName = eventName
        self.artist = artist
        self.supportArtists = supportArtists
        self.venueName = venueName
        self.venueCity = venueCity
        self.venueColorHex = venueColorHex
        self.date = date
        self.doorsTime = doorsTime
        self.showTime = showTime
        self.status = status
        self.priceMin = priceMin
        self.priceMax = priceMax
        self.ticketURL = ticketURL
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.ageRestriction = ageRestriction
    }

    // MARK: - Intrinsic accessors

    /// The call-to-action target. Prefers the venue's own event page
    /// (``sourceURL``) and falls back to the direct ``ticketURL`` — WXYC hands
    /// listeners off to the box office rather than selling tickets itself.
    /// `nil` when the source carries no link at all (the CTA then hides).
    public var ctaURL: URL? {
        sourceURL ?? ticketURL
    }

    /// The artist to match/display: the explicit ``artist`` when present, else
    /// the ``eventName``.
    public var headlineName: String {
        artist ?? eventName
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case eventName = "name"
        case artist
        case supportArtists = "support_artists"
        case venueName = "venue_name"
        case venueCity = "venue_city"
        case venueColorHex = "venue_color"
        case date
        case doorsTime = "doors_time"
        case showTime = "show_time"
        case status
        case priceMin = "price_min"
        case priceMax = "price_max"
        case ticketURL = "ticket_url"
        case sourceURL = "source_url"
        case imageURL = "image_url"
        case ageRestriction = "age_restriction"
    }

    /// Date-only parser pinned to the station zone and a fixed POSIX locale, so a
    /// `yyyy-MM-dd` value resolves to the same calendar day regardless of the
    /// device's zone or locale. Mirrors the fixed-locale approach in
    /// `Breakpoint.hourComponent`.
    static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .wxycStation
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        eventName = try container.decode(String.self, forKey: .eventName)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        supportArtists = try container.decodeIfPresent(String.self, forKey: .supportArtists)
        venueName = try container.decodeIfPresent(String.self, forKey: .venueName)
        venueCity = try container.decodeIfPresent(String.self, forKey: .venueCity)
        venueColorHex = try container.decodeIfPresent(String.self, forKey: .venueColorHex)

        let dateString = try container.decode(String.self, forKey: .date)
        guard let parsedDate = UpcomingShow.dateParser.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "Expected a yyyy-MM-dd date, got \"\(dateString)\""
            )
        }
        date = parsedDate

        doorsTime = try container.decodeIfPresent(String.self, forKey: .doorsTime)
        showTime = try container.decodeIfPresent(String.self, forKey: .showTime)
        // Absent status → `.unknown`; unrecognized value is absorbed by
        // ShowStatus's own tolerant decode.
        status = try container.decodeIfPresent(ShowStatus.self, forKey: .status) ?? .unknown
        priceMin = try container.decodeIfPresent(Double.self, forKey: .priceMin)
        priceMax = try container.decodeIfPresent(Double.self, forKey: .priceMax)
        ticketURL = try container.decodeIfPresent(URL.self, forKey: .ticketURL)
        sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        ageRestriction = try container.decodeIfPresent(String.self, forKey: .ageRestriction)
    }

    /// Encodes back to the wire shape, writing `date` as a `yyyy-MM-dd` string so
    /// a cached show round-trips (the synthesized encoder would emit a numeric
    /// `Date`, silently breaking any re-decode).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(eventName, forKey: .eventName)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(supportArtists, forKey: .supportArtists)
        try container.encodeIfPresent(venueName, forKey: .venueName)
        try container.encodeIfPresent(venueCity, forKey: .venueCity)
        try container.encodeIfPresent(venueColorHex, forKey: .venueColorHex)
        try container.encode(UpcomingShow.dateParser.string(from: date), forKey: .date)
        try container.encodeIfPresent(doorsTime, forKey: .doorsTime)
        try container.encodeIfPresent(showTime, forKey: .showTime)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(priceMin, forKey: .priceMin)
        try container.encodeIfPresent(priceMax, forKey: .priceMax)
        try container.encodeIfPresent(ticketURL, forKey: .ticketURL)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(ageRestriction, forKey: .ageRestriction)
    }
}
