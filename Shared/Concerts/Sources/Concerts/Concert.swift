//
//  Concert.swift
//  Concerts
//
//  A touring-band show in the Triangle area, as served by Backend-Service's
//  `GET /concerts` read API and embedded on the flowsheet feed. Decodes the
//  backend `Concert`/`Venue` schema in `wxyc-shared/api.yaml`
//  (WXYC/Backend-Service#1603 / #1606).
//
//  Renamed from `UpcomingShow` (which mirrored triangle-shows' `EventResponse`)
//  when the type graduated out of `Shared/Playlist` into this package: the iOS
//  client talks to Backend-Service, not triangle-shows, so the wire shape is the
//  backend `Concert`. The old flat `venue_name`/`venue_city`/`venue_color` fields
//  are now the embedded ``Venue`` (which carries no accent color — see below).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A live-music venue whose calendar WXYC ingests. Embedded whole in ``Concert``.
///
/// Mirrors the backend `Venue` schema (`wxyc-shared/api.yaml`). Only `address`
/// is nullable; everything else is always present.
///
/// - Note: The backend `Venue` has **no accent-color field**. The old
///   `UpcomingShow.venueColorHex` (used to tint the Box Office ticket glow) has
///   no source here and was dropped. If a per-venue tint is wanted later, it
///   should be derived client-side (e.g. hashed from ``slug``) rather than
///   carried on the wire.
public struct Venue: Codable, Sendable, Equatable, Hashable, Identifiable {

    /// Backend `venues.id`. Stable per venue.
    public let id: Int

    /// URL-safe venue key (e.g. `"cats-cradle"`). Stable; usable as a tint seed.
    public let slug: String

    /// Display name (e.g. `"Cat's Cradle"`).
    public let name: String

    /// City the venue is in (e.g. `"Carrboro"`).
    public let city: String

    /// Two-letter state code (e.g. `"NC"`).
    public let state: String

    /// Street address, or `nil` when the source didn't carry one.
    public let address: String?

    public init(
        id: Int,
        slug: String,
        name: String,
        city: String,
        state: String,
        address: String? = nil
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.city = city
        self.state = state
        self.address = address
    }
}

/// One affinity neighbor of a resolved concert headliner, drawn from the
/// semantic-index graph and embedded in ``Concert/similarArtists``.
///
/// Mirrors the backend `SimilarArtist` schema (`wxyc-shared/api.yaml`). The
/// ``artistId`` shares the WXYC catalog artist-id keyspace with
/// ``Concert/headliningArtistId``, so on-device For You matching can intersect
/// it against liked-artist ids in one id space (WXYC/wxyc-ios-64#493). No artist
/// name rides the wire — the reason line's name comes from the local likes
/// store, so the server never learns the listener's taste.
public struct SimilarArtist: Codable, Sendable, Equatable, Hashable {

    /// WXYC catalog artist id, same keyspace as ``Concert/headliningArtistId``.
    public let artistId: Int

    /// semantic-index affinity score; higher is closer. Drives the client-side
    /// similar-tier ranking and noise cap. Type-max normalized **per source
    /// artist**, so weights are comparable *within* one concert's neighbor list
    /// but not across concerts.
    public let weight: Double

    public init(artistId: Int, weight: Double) {
        self.artistId = artistId
        self.weight = weight
    }

    private enum CodingKeys: String, CodingKey {
        case artistId = "artist_id"
        case weight
    }
}

/// Element-tolerant wrapper for decoding a ``Concert/similarArtists`` array: a
/// neighbor object that fails to decode (a missing or non-numeric `artist_id` /
/// `weight`) becomes ``similarArtist`` `== nil` instead of throwing, so one
/// malformed element can't fail the whole `GET /concerts` page decode — the same
/// one-bad-row-can't-break-the-page discipline as ``Concert/parseURL(_:)``. The
/// caller `compactMap`s the survivors back to `[SimilarArtist]`.
private struct LossySimilarArtist: Decodable {
    let similarArtist: SimilarArtist?

    init(from decoder: Decoder) throws {
        similarArtist = try? SimilarArtist(from: decoder)
    }
}

/// An upcoming (or recent) Triangle-area concert, as rendered by the Box Office
/// ticket and browsed in the On Tour tab.
///
/// Decoding is deliberately tolerant: only the fields the backend always sends
/// (`id`, `venue`, `starts_on`, `headlining_artist_raw`, `status`) are required;
/// every nullable wire field decodes to `nil` when absent, and an unrecognized
/// `status` degrades to ``ShowStatus/unknown`` rather than throwing. The URL
/// fields (`ticket_url`, `image_url`, `event_url`) go through `URL(string:)`
/// rather than a throwing `URL(from:)`, so a present-but-empty `""` or malformed string
/// decodes to `nil` instead of failing the whole page. A partially-populated
/// concert (a common case — many scraped listings are date-only with no price
/// or times) still decodes and renders.
///
/// `supporting_artists_raw` is a required non-null array on the wire but decodes
/// to `[]` when absent, so a stray-null row can't fail the decode.
public struct Concert: Codable, Sendable, Equatable, Hashable, Identifiable {

    /// Backend `concerts.id`. Stable per concert.
    public let id: Int

    /// The venue, embedded whole. Always present.
    public let venue: Venue

    /// The venue-local calendar day of the show (US Eastern), parsed from the
    /// backend's date-only `yyyy-MM-dd` `starts_on`. Always present. Windowing
    /// and ordering in the backend are all on this field, never ``startsAt``.
    public let startsOn: Date

    /// The exact start instant, or `nil` for date-only events. An ISO-8601
    /// date-time on the wire (`starts_at`).
    public let startsAt: Date?

    /// The doors instant, or `nil`. An ISO-8601 date-time on the wire
    /// (`doors_at`).
    public let doorsAt: Date?

    /// The headlining artist as billed (`headlining_artist_raw`). Always present;
    /// this is the field matched against a playcut's artist.
    public let headliningArtistRaw: String

    /// The resolved WXYC catalog artist id when the headliner matched the
    /// library, else `nil`. `curated=true` queries return only rows where this
    /// is non-null.
    public let headliningArtistId: Int?

    /// The event's own title when it differs from the headliner (e.g. a festival
    /// or a billed night), or `nil`.
    public let title: String?

    /// Supporting acts as billed. Empty when none.
    public let supportingArtistsRaw: [String]

    /// Direct ticketing link (`ticket_url`), often a third-party seller, or
    /// `nil`. The CTA fallback target (see ``ctaURL``).
    public let ticketURL: URL?

    /// Event/promo image (`image_url`), or `nil`.
    public let imageURL: URL?

    /// The venue's own event-detail page (`event_url`), distinct from the
    /// often-third-party ``ticketURL``, or `nil` when no venue page is known.
    /// The preferred CTA target (see ``ctaURL``). A forward-compatible
    /// optional: it decodes to `nil` when the backend omits the field, so this
    /// client is stable whether or not the backend has shipped it (same
    /// discipline as ``genres``).
    public let eventURL: URL?

    /// Lowest advertised price in dollars, or `nil` when unpriced/unknown.
    public let priceMin: Double?

    /// Highest advertised price in dollars, or `nil`.
    public let priceMax: Double?

    /// Age policy string as advertised (e.g. `"All Ages"`, `"18+"`), or `nil`.
    public let ageRestriction: String?

    /// Ticket-availability state. Drives the pill and CTA wording.
    public let status: ShowStatus

    /// Discogs genre tags for the resolved headlining artist, aggregated across
    /// their releases (LML discogs-cache, majority-take), or `nil` when the
    /// headliner is unresolved or the nightly enrichment has not run yet. The chip
    /// vocabulary for the On Tour genre filter — the same coarse taxonomy the app
    /// shows as Playcut Detail genre capsules (`FlowsheetV2TrackEntry.genres`),
    /// never the internal library filing codes. A forward-compatible optional: it
    /// decodes to `nil` when the backend omits the field, so this client can ship
    /// ahead of backend emission (same discipline as the flowsheet fields).
    public let genres: [String]?

    /// Affinity neighbors of the resolved headliner, ordered by ``SimilarArtist/weight``
    /// descending (semantic-index graph, computed nightly), or `nil` when the
    /// headliner is unresolved or the enrichment has not run. Powers the on-device
    /// For You shelf: intersected against the listener's liked-artist ids entirely
    /// on-device, so no taste signal is ever sent to the server (WXYC/wxyc-ios-64#493).
    /// A forward-compatible optional: it decodes to `nil` when the backend omits
    /// the field, so this client can ship ahead of backend emission (same
    /// discipline as ``genres``).
    public let similarArtists: [SimilarArtist]?

    /// All-time WXYC flowsheet play count of the resolved (in-library) headliner,
    /// from the semantic-index graph, or `nil` when the headliner is unresolved or
    /// has no play count. **Identical for every listener** — the public
    /// station-affinity signal behind the On Tour For You shelf's cold-start tier,
    /// which surfaces heavily-played artists even for a listener with no likes. It
    /// is not personalized and carries no listener data, so intersecting it changes
    /// nothing about the privacy invariant. Unlike ``SimilarArtist/weight`` (a
    /// per-list normalized score) this is a genuine global scalar, so it ranks
    /// validly across concerts. A forward-compatible optional: it decodes to `nil`
    /// when the backend omits the field, so this client can ship ahead of backend
    /// emission (same discipline as ``genres`` / ``similarArtists``).
    public let stationPlays: Int?

    /// Whether the station editorially recommends this concert (`station_recommended`),
    /// the boolean signal behind the For You shelf's cold-start "WXYC recommends"
    /// tier (WXYC/wxyc-shared#244, emitted by WXYC/Backend-Service#1731).
    /// **Identical for every listener** — like ``stationPlays`` it is not
    /// personalized and carries no listener data, so reading it changes nothing
    /// about the privacy invariant. A forward-compatible default: absent or null
    /// on the wire decodes to `false`, so this client can ship ahead of backend
    /// emission (same discipline as ``genres`` / ``similarArtists``).
    public let stationRecommended: Bool

    /// The 1-based rank of this concert among all station-recommended concerts,
    /// by all-time WXYC flowsheet plays of the resolved headliner (rank 1 =
    /// most-played) — `station_recommended_rank`, the server-computed cap
    /// signal behind the For You shelf's "WXYC recommends" tier
    /// (WXYC/wxyc-ios-64#594, emitted by WXYC/Backend-Service#1756). Non-null
    /// exactly when ``stationRecommended`` is true; `nil` otherwise.
    /// **Identical for every listener** — like ``stationPlays`` it is not
    /// personalized and carries no listener data, so reading it changes
    /// nothing about the privacy invariant. A forward-compatible optional: it
    /// decodes to `nil` when the backend omits or nulls the field, so this
    /// client can ship ahead of backend emission (same discipline as
    /// ``stationPlays``).
    public let stationRecommendedRank: Int?

    /// Artist biography for the resolved headliner, drawn from their Discogs
    /// profile (raw Discogs markup, parsed client-side), cached nightly on the
    /// backend and keyed by the effective Discogs artist id. `nil` when the
    /// headliner is unresolved, has no Discogs profile, or the enrichment has
    /// not run. **Identical for every listener** — like ``stationRecommended``
    /// it is not personalized and carries no listener data. The text behind the
    /// On Tour concert-detail "About the Artist" card. A forward-compatible
    /// optional: absent or explicit-null `artist_bio` decodes to `nil`, so this
    /// client can ship ahead of backend emission (same discipline as ``genres``
    /// / ``similarArtists``).
    public let artistBio: String?

    public init(
        id: Int,
        venue: Venue,
        startsOn: Date,
        startsAt: Date? = nil,
        doorsAt: Date? = nil,
        headliningArtistRaw: String,
        headliningArtistId: Int? = nil,
        title: String? = nil,
        supportingArtistsRaw: [String] = [],
        ticketURL: URL? = nil,
        imageURL: URL? = nil,
        eventURL: URL? = nil,
        priceMin: Double? = nil,
        priceMax: Double? = nil,
        ageRestriction: String? = nil,
        status: ShowStatus,
        genres: [String]? = nil,
        similarArtists: [SimilarArtist]? = nil,
        stationPlays: Int? = nil,
        stationRecommended: Bool = false,
        stationRecommendedRank: Int? = nil,
        artistBio: String? = nil
    ) {
        self.id = id
        self.venue = venue
        self.startsOn = startsOn
        self.startsAt = startsAt
        self.doorsAt = doorsAt
        self.headliningArtistRaw = headliningArtistRaw
        self.headliningArtistId = headliningArtistId
        self.title = title
        self.supportingArtistsRaw = supportingArtistsRaw
        self.ticketURL = ticketURL
        self.imageURL = imageURL
        self.eventURL = eventURL
        self.priceMin = priceMin
        self.priceMax = priceMax
        self.ageRestriction = ageRestriction
        self.status = status
        self.genres = genres
        self.similarArtists = similarArtists
        self.stationPlays = stationPlays
        self.stationRecommended = stationRecommended
        self.stationRecommendedRank = stationRecommendedRank
        self.artistBio = artistBio
    }

    // MARK: - Intrinsic accessors

    /// The call-to-action target — the venue's own event page when known
    /// (``eventURL``), else the direct ticket link (``ticketURL``). `nil` when
    /// the concert carries no link at all (the CTA then hides).
    ///
    /// The precedence matches the `event_url` contract in `wxyc-shared/api.yaml`
    /// ("clients fall back to `ticket_url`"), restored to the schema by
    /// WXYC/Backend-Service#1609 — the same preference the old `UpcomingShow`
    /// expressed via `source_url`. The Box Office presenter keys its "venue
    /// page" vs "ticket page" CTA wording off which branch resolves.
    public var ctaURL: URL? {
        eventURL ?? ticketURL
    }

    /// The artist to match/display: the ``title`` when the source gave the event
    /// its own name, else the billed headliner ``headliningArtistRaw``.
    public var headlineName: String {
        title ?? headliningArtistRaw
    }

    /// The canonical public share link — `https://wxyc.org/shows/<id>`. The one
    /// place the share-URL shape lives, so every emitting surface (the On Tour
    /// detail's share button, the row context menu, and future widgets/Spotlight
    /// entities) produces the same link. Resolved by the `wxyc-links-registry`
    /// Cloudflare Worker: an app owner deep-links into this detail, everyone else
    /// lands on the OG-tagged share page. The AASA registers `/shows/*`, so the
    /// path word is "shows" (the tab's voice), not the API's "concerts".
    ///
    /// Non-optional: ``id`` is an `Int`, so the interpolation is always a valid
    /// URL — the same known-good-literal idiom the app uses for its stream and
    /// API base URLs.
    public var shareURL: URL {
        URL(string: "https://wxyc.org/shows/\(id)")!
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case venue
        case startsOn = "starts_on"
        case startsAt = "starts_at"
        case doorsAt = "doors_at"
        case headliningArtistRaw = "headlining_artist_raw"
        case headliningArtistId = "headlining_artist_id"
        case title
        case supportingArtistsRaw = "supporting_artists_raw"
        case ticketURL = "ticket_url"
        case imageURL = "image_url"
        case eventURL = "event_url"
        case priceMin = "price_min"
        case priceMax = "price_max"
        case ageRestriction = "age_restriction"
        case status
        case genres
        case similarArtists = "similar_artists"
        case stationPlays = "station_plays"
        case stationRecommended = "station_recommended"
        case stationRecommendedRank = "station_recommended_rank"
        case artistBio = "artist_bio"
    }

    /// Date-only parser pinned to the station zone and a fixed POSIX locale, so a
    /// `yyyy-MM-dd` `starts_on` resolves to the same calendar day regardless of
    /// the device's zone or locale. Mirrors the fixed-locale approach in
    /// `Breakpoint.hourComponent`.
    static let dateParser = DateFormatter.station("yyyy-MM-dd")

    /// Builds an ISO-8601 instant parser. Created per call rather than held as a
    /// `static let` because `ISO8601DateFormatter` is not `Sendable` and cannot
    /// back a concurrency-safe global. `withFractionalSeconds` covers the backend
    /// serialization (`Date.toISOString()` → `...T20:00:00.000Z`); the fallback
    /// without it covers a `...T20:00:00Z`-shaped instant.
    private static func makeInstantParser(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    /// Formats a `Date` as an ISO-8601 instant with fractional seconds, matching
    /// the backend wire shape, for the encode path.
    static func formatInstant(_ date: Date) -> String {
        makeInstantParser(fractionalSeconds: true).string(from: date)
    }

    /// Parses an ISO-8601 instant string tolerantly (with or without fractional
    /// seconds), returning `nil` for an unparseable or absent value.
    static func parseInstant(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return makeInstantParser(fractionalSeconds: true).date(from: raw)
            ?? makeInstantParser(fractionalSeconds: false).date(from: raw)
    }

    /// Parses a URL string tolerantly, returning `nil` for an absent, empty, or
    /// malformed value instead of throwing. The backend stores an unknown link
    /// as `""` verbatim (the scrapers don't coerce empty → null), so decoding a
    /// URL field as `URL(from:)` would throw `DecodingError.dataCorrupted` and
    /// fail the whole page decode; going through `URL(string:)` degrades a bad
    /// value to `nil` per the tolerant-decode contract above.
    static func parseURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        venue = try container.decode(Venue.self, forKey: .venue)

        let startsOnString = try container.decode(String.self, forKey: .startsOn)
        guard let parsedDate = Concert.dateParser.date(from: startsOnString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .startsOn,
                in: container,
                debugDescription: "Expected a yyyy-MM-dd starts_on, got \"\(startsOnString)\""
            )
        }
        startsOn = parsedDate

        startsAt = Concert.parseInstant(try container.decodeIfPresent(String.self, forKey: .startsAt))
        doorsAt = Concert.parseInstant(try container.decodeIfPresent(String.self, forKey: .doorsAt))

        headliningArtistRaw = try container.decode(String.self, forKey: .headliningArtistRaw)
        headliningArtistId = try container.decodeIfPresent(Int.self, forKey: .headliningArtistId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        // Required non-null array on the wire, but coalesce a NULL/absent value
        // to [] so a stray null can't break the decode.
        supportingArtistsRaw = try container.decodeIfPresent([String].self, forKey: .supportingArtistsRaw) ?? []
        // URL fields decode via String? → URL(string:) rather than
        // decodeIfPresent(URL.self): Foundation's URL(from:) THROWS
        // DecodingError.dataCorrupted on a present-but-empty "" (or otherwise
        // malformed) string, and since a page is a strict [Concert] array one
        // bad row would fail the whole page decode. URL(string:) returns nil for
        // "" and malformed strings, keeping the decode tolerant.
        ticketURL = Concert.parseURL(try container.decodeIfPresent(String.self, forKey: .ticketURL))
        imageURL = Concert.parseURL(try container.decodeIfPresent(String.self, forKey: .imageURL))
        eventURL = Concert.parseURL(try container.decodeIfPresent(String.self, forKey: .eventURL))
        priceMin = try container.decodeIfPresent(Double.self, forKey: .priceMin)
        priceMax = try container.decodeIfPresent(Double.self, forKey: .priceMax)
        ageRestriction = try container.decodeIfPresent(String.self, forKey: .ageRestriction)
        // Absent status → `.unknown`; unrecognized value is absorbed by
        // ShowStatus's own tolerant decode.
        status = try container.decodeIfPresent(ShowStatus.self, forKey: .status) ?? .unknown
        // Forward-compatible optional: absent or explicit-null `genres` → nil, so
        // this decode is stable whether or not the backend has shipped the field.
        genres = try container.decodeIfPresent([String].self, forKey: .genres)
        // Forward-compatible AND element-tolerant, extending the `genres`
        // discipline with the URL fields' one-bad-row guard: absent or
        // explicit-null `similar_artists` → nil (unresolved headliner or
        // pre-enrichment), while a present array drops any malformed neighbor
        // rather than throwing and failing the whole page decode. An array whose
        // elements are all malformed decodes to [] — which the For You engine
        // treats identically to nil.
        similarArtists = try container
            .decodeIfPresent([LossySimilarArtist].self, forKey: .similarArtists)?
            .compactMap(\.similarArtist)
        // Forward-compatible optional: absent or explicit-null `station_plays` →
        // nil (unresolved headliner or pre-enrichment), so this decode is stable
        // whether or not the backend has shipped the field.
        stationPlays = try container.decodeIfPresent(Int.self, forKey: .stationPlays)
        // Forward-compatible default: absent or explicit-null `station_recommended`
        // → false (not recommended), so this decode is stable whether or not the
        // backend has shipped the field.
        stationRecommended = try container.decodeIfPresent(Bool.self, forKey: .stationRecommended) ?? false
        // Forward-compatible optional: absent or explicit-null
        // `station_recommended_rank` → nil (a non-gated concert, or the backend
        // hasn't shipped the field yet), so this decode is stable whether or
        // not the backend has shipped the field.
        stationRecommendedRank = try container.decodeIfPresent(Int.self, forKey: .stationRecommendedRank)
        // Forward-compatible optional: absent or explicit-null `artist_bio` →
        // nil (unresolved headliner, no Discogs profile, or pre-enrichment), so
        // this decode is stable whether or not the backend has shipped the field.
        artistBio = try container.decodeIfPresent(String.self, forKey: .artistBio)
    }

    /// Encodes back to the wire shape, writing `starts_on` as a `yyyy-MM-dd`
    /// string and the instants as ISO-8601 so a cached concert round-trips (the
    /// synthesized encoder would emit numeric `Date`s, silently breaking any
    /// re-decode).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(venue, forKey: .venue)
        try container.encode(Concert.dateParser.string(from: startsOn), forKey: .startsOn)
        try container.encodeIfPresent(startsAt.map(Concert.formatInstant), forKey: .startsAt)
        try container.encodeIfPresent(doorsAt.map(Concert.formatInstant), forKey: .doorsAt)
        try container.encode(headliningArtistRaw, forKey: .headliningArtistRaw)
        try container.encodeIfPresent(headliningArtistId, forKey: .headliningArtistId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(supportingArtistsRaw, forKey: .supportingArtistsRaw)
        try container.encodeIfPresent(ticketURL, forKey: .ticketURL)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(eventURL, forKey: .eventURL)
        try container.encodeIfPresent(priceMin, forKey: .priceMin)
        try container.encodeIfPresent(priceMax, forKey: .priceMax)
        try container.encodeIfPresent(ageRestriction, forKey: .ageRestriction)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(genres, forKey: .genres)
        try container.encodeIfPresent(similarArtists, forKey: .similarArtists)
        try container.encodeIfPresent(stationPlays, forKey: .stationPlays)
        try container.encode(stationRecommended, forKey: .stationRecommended)
        try container.encodeIfPresent(stationRecommendedRank, forKey: .stationRecommendedRank)
        try container.encodeIfPresent(artistBio, forKey: .artistBio)
    }
}
