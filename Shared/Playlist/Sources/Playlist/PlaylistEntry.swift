//
//  PlaylistEntry.swift
//  Playlist
//
//  Defines the core playlist data models including Playcut, Breakpoint, Talkset, ShowMarker,
//  and the Playlist container type that aggregates all entry types from the WXYC API.
//
//  Created by Jake Bromberg on 04/16/20.
//  Copyright © 2020 WXYC. All rights reserved.
//

import Concerts
import Core
import Foundation
import Logger

extension URL {
#if WXYC_320_STREAM_ENABLED
    static let WXYCStream320kMP3 = URL(string: "https://audio-mp3.ibiblio.org:8000/wxyc-alt.mp3")!
#endif
}

public protocol PlaylistEntry: Codable, Identifiable, Sendable, Equatable, Hashable, Comparable {
    var id: UInt64 { get }
    var hour: UInt64 { get }
    var chronOrderID: UInt64 { get }
    var timeCreated: UInt64 { get }
}

public extension PlaylistEntry {
    /// Orders by `chronOrderID`, then `id` as an explicit, deterministic
    /// tiebreak.
    ///
    /// Duplicate `chronOrderID`s are reachable (see the composite-key doc
    /// comment on `FlowsheetConverter.chronOrderID(showID:playOrder:id:)`),
    /// and a bare `chronOrderID` comparison would leave same-type collections
    /// — e.g. `PlaycutHistoryStore`'s `[Playcut].sorted(by: >)` — in an
    /// unspecified relative order for tied elements across calls. `id` is
    /// row identity for anything that came off the flowsheet, so it resolves
    /// the tie there.
    ///
    /// It does *not* make this a total order in general: entries synthesized
    /// outside the feed carry placeholder identity — `LikedSongSnapshot`'s
    /// `toPlaycut()` hands every bridged row `id: 0, chronOrderID: 0` — so a
    /// collection of those stays fully tied, with *no guaranteed relative
    /// order*: Swift's `sorted` makes no stability promise, so tied elements
    /// may present differently across calls. That is tolerable on their side
    /// (nothing keys on a liked song's flowsheet identity or its position),
    /// but callers that need a stable order over mixed or synthesized
    /// entries must sort on something else.
    static func <(lhs: Self, rhs: Self) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    /// The ordering rule itself, in one place.
    ///
    /// `<` above can't serve the heterogeneous timeline — `Comparable` carries
    /// a `Self` requirement, so a `[any PlaylistEntry]` of mixed concrete types
    /// can't call it — and `isOrderedNewestFirst` exists for that case. Both
    /// read this, so the two can't drift apart the way two hand-written
    /// `(chronOrderID, id)` comparisons would.
    var sortKey: (chronOrderID: UInt64, id: UInt64) {
        (chronOrderID, id)
    }

    /// The moment of broadcast: `hour` (milliseconds since the Unix epoch) as a `Date`.
    var broadcastDate: Date {
        Date(timeIntervalSince1970: Double(hour) / 1000)
    }
}

/// Coding keys shared by every ``PlaylistEntry`` decoder: the four fields that
/// begin every v1/v2 flowsheet row. Each conformer's own `CodingKeys` enum
/// additionally conforms to this so it can be decoded through
/// ``PlaylistEntryHeader``.
protocol PlaylistEntryCodingKeys: CodingKey {
    static var id: Self { get }
    static var hour: Self { get }
    static var chronOrderID: Self { get }
    static var timeCreated: Self { get }
}

/// The header fields common to every ``PlaylistEntry`` variant, decoded once
/// instead of repeating the four-line `id`/`hour`/`chronOrderID`/`timeCreated`
/// block (plus the `timeCreated ?? hour` fallback for feeds that predate that
/// field) in each of `Breakpoint`, `Talkset`, `ShowMarker`, and `Playcut`.
struct PlaylistEntryHeader {
    let id: UInt64
    let hour: UInt64
    let chronOrderID: UInt64
    let timeCreated: UInt64

    init<Keys: PlaylistEntryCodingKeys>(from container: KeyedDecodingContainer<Keys>) throws {
        id = try container.decode(UInt64.self, forKey: .id)
        hour = try container.decode(UInt64.self, forKey: .hour)
        chronOrderID = try container.decode(UInt64.self, forKey: .chronOrderID)
        // Older feeds predate `timeCreated`; fall back to `hour`, same as the
        // per-type decoders this replaces.
        timeCreated = try container.decodeIfPresent(UInt64.self, forKey: .timeCreated) ?? hour
    }
}

public struct Breakpoint: PlaylistEntry {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
    public let timeCreated: UInt64

    public init(id: UInt64, hour: UInt64, chronOrderID: UInt64, timeCreated: UInt64) {
        self.id = id
        self.hour = hour
        self.chronOrderID = chronOrderID
        self.timeCreated = timeCreated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let header = try PlaylistEntryHeader(from: container)
        self.id = header.id
        self.hour = header.hour
        self.chronOrderID = header.chronOrderID
        self.timeCreated = header.timeCreated
    }

    private enum CodingKeys: String, CodingKey, PlaylistEntryCodingKeys {
        case id, hour, chronOrderID, timeCreated
    }

    public var formattedDate: String {
        hourLabel()
    }

    /// Renders the breakpoint's hour anchored to the station's time zone.
    ///
    /// A listener already in the station's zone sees the hour once, e.g.
    /// `"3PM ET"`. A listener elsewhere sees their local hour first, then the
    /// station's, e.g. `"12PM PT / 3PM ET"`.
    ///
    /// The label vocabulary is intentionally fixed US-English (see `labelLocale`):
    /// the station's schedule is inherently US Eastern and the compact zone
    /// abbreviations ("ET", "PT") only exist in English, so the output does not
    /// vary with the device locale.
    ///
    /// - Parameters:
    ///   - localTimeZone: The listener's time zone. Defaults to the device's.
    ///   - stationTimeZone: The station's broadcast zone. Defaults to Eastern.
    /// - Returns: The formatted hour-marker label.
    func hourLabel(
        localTimeZone: TimeZone = .current,
        stationTimeZone: TimeZone = .wxycStation
    ) -> String {
        let date = broadcastDate
        let station = Self.hourComponent(for: date, in: stationTimeZone)
        // Same UTC offset means the listener already reads station time; collapse
        // to a single label rather than printing the same hour twice.
        guard localTimeZone.secondsFromGMT(for: date) != stationTimeZone.secondsFromGMT(for: date) else {
            return station
        }
        let local = Self.hourComponent(for: date, in: localTimeZone)
        return "\(local) / \(station)"
    }

    /// Fixed locale for the hour-marker label. The vocabulary ("ET", "PT", "AM",
    /// "PM") is deliberately US-English and must not change with the device
    /// locale, so both the hour format and the `.shortGeneric` zone name are
    /// resolved against `en_US_POSIX` rather than `.current` — which would yield
    /// e.g. `"3p. m. hora de Nueva York"` on a Spanish device.
    private static let labelLocale = Locale(identifier: "en_US_POSIX")

    /// Formats a single `"<hour><AM/PM> <zone>"` component, e.g. `"3PM ET"`.
    private static func hourComponent(for date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = labelLocale
        formatter.timeZone = timeZone
        formatter.dateFormat = "ha"
        let hour = formatter.string(from: date)
        let zone = timeZone.localizedName(for: .shortGeneric, locale: labelLocale)
            ?? timeZone.abbreviation(for: date)
            ?? ""
        return "\(hour) \(zone)"
    }
}

public struct Talkset: PlaylistEntry {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
    public let timeCreated: UInt64

    public init(id: UInt64, hour: UInt64, chronOrderID: UInt64, timeCreated: UInt64) {
        self.id = id
        self.hour = hour
        self.chronOrderID = chronOrderID
        self.timeCreated = timeCreated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let header = try PlaylistEntryHeader(from: container)
        self.id = header.id
        self.hour = header.hour
        self.chronOrderID = header.chronOrderID
        self.timeCreated = header.timeCreated
    }

    private enum CodingKeys: String, CodingKey, PlaylistEntryCodingKeys {
        case id, hour, chronOrderID, timeCreated
    }
}

/// Represents a show start or end marker from the v2 API.
public struct ShowMarker: PlaylistEntry {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
    public let timeCreated: UInt64
    public let isStart: Bool
    public let djName: String?
    public let message: String

    public init(
        id: UInt64,
        hour: UInt64,
        chronOrderID: UInt64,
        timeCreated: UInt64,
        isStart: Bool,
        djName: String?,
        message: String
    ) {
        self.id = id
        self.hour = hour
        self.chronOrderID = chronOrderID
        self.timeCreated = timeCreated
        self.isStart = isStart
        self.djName = djName
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let header = try PlaylistEntryHeader(from: container)
        self.id = header.id
        self.hour = header.hour
        self.chronOrderID = header.chronOrderID
        self.timeCreated = header.timeCreated
        self.isStart = try container.decode(Bool.self, forKey: .isStart)
        self.djName = try container.decodeIfPresent(String.self, forKey: .djName)
        self.message = try container.decode(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey, PlaylistEntryCodingKeys {
        case id, hour, chronOrderID, timeCreated, isStart, djName, message
    }
}

public extension ShowMarker {
    /// Title for the on-air banner — the DJ's name.
    ///
    /// Falls back to the station name ("WXYC") when the flowsheet carries no DJ name,
    /// e.g. an unnamed sign-on or automation.
    var onAirTitle: String {
        djName ?? "WXYC"
    }

    /// Label for the marker's inline timeline row — "DJ Moo signed on",
    /// "DJ Moo signed off".
    ///
    /// Lives here rather than in the view so the copy sits beside
    /// ``onAirTitle``, the other string this type spells for a surface, and so
    /// both are covered by the same tests.
    ///
    /// Total over both directions even though ``Playlist/timelineEntries``
    /// currently filters every sign-on out of the feed, so only the sign-off
    /// half reaches a row today. Which markers render is that filter's policy
    /// to state, not this property's to bake in — the same split as
    /// ``onAirTitle``, which is only meaningful for a sign-on yet is defined
    /// for every marker.
    ///
    /// An absent DJ name degrades to a generic subject — "Previous DJ signed
    /// off", "Next DJ signed on" — rather than borrowing ``onAirTitle``'s
    /// station-name fallback, which would read "WXYC signed off" and assert
    /// the station itself left the air.
    ///
    /// The direction words are relative to the feed's newest-first order,
    /// where a marker labels the block below it: the DJ who signed off is the
    /// one whose show follows underneath the row, and the DJ who signed on is
    /// the one whose show sits above it.
    ///
    /// Backend sends an empty `dj_name` on a small fraction of sign-offs (2 of
    /// 108 shows sampled over 12 days), which `FlowsheetEntryType` folds to
    /// nil, so this is a row the feed really renders.
    var timelineLabel: String {
        switch (djName, isStart) {
        case (let name?, true): "\(name) signed on"
        case (let name?, false): "\(name) signed off"
        case (nil, true): "Next DJ signed on"
        case (nil, false): "Previous DJ signed off"
        }
    }
}

public struct Playcut: PlaylistEntry, Hashable {
    public let id: UInt64
    public let hour: UInt64
    public let chronOrderID: UInt64
    public let timeCreated: UInt64

    public let songTitle: String
    public let labelName: String?
    public let artistName: String
    public let releaseTitle: String?

    /// Whether this playcut is a rotation play (station library track).
    /// Rotation plays have their artwork cached longer than non-rotation plays.
    public let rotation: Bool

    // MARK: - Inline Metadata (v2 API)

    /// Album artwork URL from backend metadata enrichment.
    public let artworkURL: URL?

    /// Discogs release page URL.
    public let discogsURL: URL?

    /// Album release year.
    public let releaseYear: Int?

    /// Spotify track URL.
    public let spotifyURL: URL?

    /// Apple Music track URL.
    public let appleMusicURL: URL?

    /// YouTube Music track URL.
    public let youtubeMusicURL: URL?

    /// Bandcamp track URL.
    public let bandcampURL: URL?

    /// SoundCloud track URL.
    public let soundcloudURL: URL?

    /// Artist biography from Discogs.
    public let artistBio: String?

    /// Artist Wikipedia page URL.
    public let artistWikipediaURL: URL?

    /// Discogs genre classifications for the release.
    public let genres: [String]?

    /// Discogs style classifications (more specific than genres).
    public let styles: [String]?

    /// Resolved catalog artist id for this play, from the v2 flowsheet's
    /// `artist_id` (api.yaml 1.19.0, BS#1625) — the `artists.id` keyspace shared
    /// with `Concert.headliningArtistId`, which is what lets on-device likes
    /// match concerts. `nil` for free-text plays (no catalog link), the v1 API,
    /// and feeds that predate the field. Additive and nullable, exactly like the
    /// ``artistBio`` metadata precedent.
    public let artistId: Int?

    /// An upcoming Triangle-area show for this track's artist, embedded on the
    /// flowsheet feed by Backend-Service when the played track's resolved artist
    /// matches a curated upcoming concert (the soonest one). `nil` when the artist
    /// has no matching upcoming show, or when decoding a feed that predates the
    /// field. This is what drives the Box Office ticket CTA — it rides the
    /// already-fetched feed, so rendering the CTA makes no additional network call.
    ///
    /// Decodes the same backend `Concert` schema the `Concerts` package defines,
    /// so iOS decodes one type everywhere. Additive and nullable, exactly like the
    /// ``artistBio`` metadata precedent above.
    public let upcomingShow: Concert?

    /// Attributed external critic-review snippets for this play's resolved
    /// album (ADR 0012), embedded on the flowsheet feed by Backend-Service at
    /// feed-assembly time (`FlowsheetEntry.critic_reviews`, api.yaml 1.23.0).
    /// `nil` when the resolved album has no reviews, when Backend's
    /// critic-reviews attach is off, or when decoding a feed that predates
    /// the field. Reuses the same `CriticReviewItem` wire shape the metadata
    /// proxy already serves, so iOS decodes one ``CriticReview`` domain type
    /// across both surfaces — see `PlaycutMetadataService.mapCriticReviews`,
    /// which applies the identical URL-validation policy via
    /// `CriticReview.validated(_:)`. This is what lets a terminal
    /// (`enrichedMatch`) row render `ReviewsSection` straight from the feed,
    /// with no `/proxy/metadata/album` round-trip (#695).
    public let criticReviews: [CriticReview]?

    /// Server-side enrichment lifecycle for this row (`FlowsheetEntry.metadata_status`,
    /// `MetadataStatus`). `nil` for the v1 API, feeds that predate the field, and rows
    /// the backend hasn't attempted enrichment on yet in a way that emitted the field.
    /// Drives Spotlight re-donation on a terminal transition — see
    /// `PlaylistService.terminalMetadataTransitions()` (issue #443).
    public let metadataStatus: MetadataStatus?

    /// MD-set marker indicating this release is intentionally not on Discogs
    /// (embargoed promo, audience-segment release, etc.) — the "Not on
    /// Discogs" flag epic (Backend-Service#1280, `wxyc-shared` `Album`
    /// schema). When `true`, artwork rendering should suppress the
    /// Discogs-derived artwork/URL and fall back to a placeholder rather than
    /// keep showing a preserved false match (issue #390).
    ///
    /// Backend-Service emits this on the V2 flowsheet-entry embed as well as on
    /// the on-demand `/proxy/metadata/album` response (WXYC/Backend-Service#1908).
    /// Both sides gate on the row having resolved to a library album rather than
    /// on the flag's value, and `library.discogs_unavailable` is
    /// `NOT NULL DEFAULT false` — so `false` is what arrives for the vast
    /// majority of library-linked plays, and `nil` means "no library row"
    /// (a free-text play) rather than "not flagged." Read the value, never the
    /// presence; ``Metadata/AlbumMetadata/isSparse`` documents what keying on
    /// presence cost.
    public let discogsUnavailable: Bool?

    /// Optional free-text reason for ``discogsUnavailable``, surfaced as
    /// secondary text alongside the placeholder when present. Emitted on its own
    /// `!= null` check, so it can arrive without the boolean beside it.
    public let discogsUnavailableNote: String?

    /// Whether this playcut carries inline metadata from the v2 flowsheet API.
    ///
    /// True when the row's `metadataStatus` is terminal (`enrichedMatch`/
    /// `enrichedNoMatch`/`failedNoRetry` — enrichment is done, so render from
    /// whatever inline fields exist, even zero of them, rather than issuing a
    /// degradable `/proxy/metadata/album` fetch) OR when any of the 12 inline
    /// enriched fields is present. `artistId` (a likes key), `upcomingShow`
    /// (a touring CTA), and `criticReviews` (gated independently by
    /// `AlbumMetadata.hasCriticReviews` / `CriticReviewsFeature.shouldShowReviews`
    /// — #695) are excluded — none of the three is playcut-detail metadata in
    /// the sense this predicate cares about. See #685: checking only
    /// artwork/Discogs/Spotify classified sparse-but-valid terminal rows as
    /// "no metadata."
    ///
    /// This field list is duplicated by hand in two other places that must be
    /// kept in sync when a field is added or removed: the `Playcut` decoder's
    /// `CodingKeys`/`init(from:)` above, and the inline `PlaycutMetadata`
    /// construction in `PlaycutMetadataResolver.inlineMetadata(for:)`
    /// (`Metadata`). There's no compiler-enforced link between the three —
    /// #685 itself was partly a fix for one such drift (`artworkURL` was in
    /// this predicate but missing from the resolver's builder). `artistId` and
    /// `upcomingShow` are decoded onto `Playcut` (so they do appear in the
    /// decoder) but have no `PlaycutMetadata`/`AlbumMetadata` counterpart, so
    /// they never appear in the resolver's builder either. `criticReviews` is
    /// different: `AlbumMetadata` *does* have a `criticReviews` field, so it
    /// rides along in the decoder AND the resolver's builder (#695) — it's
    /// just excluded from this predicate specifically, exactly like the other
    /// two. `discogsUnavailable`/`discogsUnavailableNote` (#390) follow the
    /// `criticReviews` shape exactly: they ride the decoder and the resolver's
    /// builder (so the render gate can see them) but are excluded here too —
    /// a suppression flag isn't "does this row have enrichment metadata" in
    /// the sense this predicate cares about.
    public var hasV2Metadata: Bool {
        metadataStatus?.isTerminal == true
            || artworkURL != nil
            || discogsURL != nil
            || releaseYear != nil
            || spotifyURL != nil
            || appleMusicURL != nil
            || youtubeMusicURL != nil
            || bandcampURL != nil
            || soundcloudURL != nil
            || artistBio != nil
            || artistWikipediaURL != nil
            || !(genres ?? []).isEmpty
            || !(styles ?? []).isEmpty
    }

    private enum CodingKeys: String, CodingKey, PlaylistEntryCodingKeys {
        case id
        case hour
        case chronOrderID
        case timeCreated
        case songTitle
        case labelName
        case artistName
        case releaseTitle
        case rotation
        case artworkURL
        case discogsURL
        case releaseYear
        case spotifyURL
        case appleMusicURL
        case youtubeMusicURL
        case bandcampURL
        case soundcloudURL
        case artistBio
        case artistWikipediaURL
        case genres
        case styles
        case artistId
        // The wire field is snake_case (the backend `Concert` embed), unlike the
        // camelCase legacy playcut keys around it. Named to match the contract so
        // the value round-trips through `Concert`'s own snake_case Codable.
        case upcomingShow = "upcoming_show"
        // Same rationale as `upcomingShow` above: matches the flowsheet's
        // snake_case `critic_reviews` wire key so this round-trips consistently.
        case criticReviews = "critic_reviews"
        case metadataStatus
        case discogsUnavailable
        case discogsUnavailableNote
    }

    public init(
        id: UInt64,
        hour: UInt64,
        chronOrderID: UInt64,
        timeCreated: UInt64,
        songTitle: String,
        labelName: String?,
        artistName: String,
        releaseTitle: String?,
        rotation: Bool = false,
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
        metadataStatus: MetadataStatus? = nil,
        discogsUnavailable: Bool? = nil,
        discogsUnavailableNote: String? = nil
    ) {
        self.id = id
        self.hour = hour
        self.chronOrderID = chronOrderID
        self.timeCreated = timeCreated
        self.songTitle = songTitle
        self.labelName = labelName
        self.artistName = artistName
        self.releaseTitle = releaseTitle
        self.rotation = rotation
        self.artworkURL = artworkURL
        self.discogsURL = discogsURL
        self.releaseYear = releaseYear
        self.spotifyURL = spotifyURL
        self.appleMusicURL = appleMusicURL
        self.youtubeMusicURL = youtubeMusicURL
        self.bandcampURL = bandcampURL
        self.soundcloudURL = soundcloudURL
        self.artistBio = artistBio
        self.artistWikipediaURL = artistWikipediaURL
        self.genres = genres
        self.styles = styles
        self.artistId = artistId
        self.upcomingShow = upcomingShow
        self.criticReviews = criticReviews
        self.metadataStatus = metadataStatus
        self.discogsUnavailable = discogsUnavailable
        self.discogsUnavailableNote = discogsUnavailableNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let header = try PlaylistEntryHeader(from: container)
        self.id = header.id
        self.hour = header.hour
        self.chronOrderID = header.chronOrderID
        self.timeCreated = header.timeCreated

        do {
            self.songTitle = try container.decode(String.self, forKey: .songTitle).htmlDecoded
            self.labelName = try container.decodeIfPresent(String.self, forKey: .labelName)?.htmlDecoded
            self.artistName = try container.decode(String.self, forKey: .artistName).htmlDecoded
            self.releaseTitle = try container.decodeIfPresent(String.self, forKey: .releaseTitle)?.htmlDecoded

            // Tolerates a string ("true"/"false") as well as a Bool. Nothing this
            // build fetches sends the string form — `FlowsheetConverter` supplies a
            // Bool, and the cache round-trips one through the synthesized
            // `encode(to:)` — so on its own this branch is dead code.
            //
            // It is retained deliberately, and it is not retained alone: it is what
            // keeps `BS2103EnrichedDecodingTests`, `BS2105OnAirDecodingTests` and
            // `PlaylistDecodingTests` able to decode the legacy `wxyc.info` grouped
            // payload, whose `rotation` is a string. Those suites are the iOS half of
            // a wire contract that App Store builds through 3.2 still depend on — that
            // feed is live and enriched, and ~10 installs were still polling it in the
            // 14 days to 2026-09-10.
            //
            // So this branch and those three suites are ONE unit with ONE lifetime:
            // retire them together once the 3.2 cohort has drained, and not before.
            // Deleting this line alone silently breaks all three suites; deleting the
            // suites alone leaves this branch genuinely dead. See #262.
            if let rotationBool = try? container.decodeIfPresent(Bool.self, forKey: .rotation) {
                self.rotation = rotationBool
            } else if let rotationString = try container.decodeIfPresent(String.self, forKey: .rotation) {
                self.rotation = rotationString.lowercased() == "true"
            } else {
                self.rotation = false
            }

            self.artworkURL = try container.decodeIfPresent(URL.self, forKey: .artworkURL)
            self.discogsURL = try container.decodeIfPresent(URL.self, forKey: .discogsURL)
            self.releaseYear = try container.decodeIfPresent(Int.self, forKey: .releaseYear)
            self.spotifyURL = try container.decodeIfPresent(URL.self, forKey: .spotifyURL)
            self.appleMusicURL = try container.decodeIfPresent(URL.self, forKey: .appleMusicURL)
            self.youtubeMusicURL = try container.decodeIfPresent(URL.self, forKey: .youtubeMusicURL)
            self.bandcampURL = try container.decodeIfPresent(URL.self, forKey: .bandcampURL)
            self.soundcloudURL = try container.decodeIfPresent(URL.self, forKey: .soundcloudURL)
            self.artistBio = try container.decodeIfPresent(String.self, forKey: .artistBio)
            self.artistWikipediaURL = try container.decodeIfPresent(URL.self, forKey: .artistWikipediaURL)
            self.genres = try container.decodeIfPresent([String].self, forKey: .genres)
            self.styles = try container.decodeIfPresent([String].self, forKey: .styles)
            self.artistId = try container.decodeIfPresent(Int.self, forKey: .artistId)
            // Optional, additive, and tolerant: an absent/null embed decodes to
            // `nil`, `Concert`'s own tolerant decode absorbs an unknown status, and
            // a present-but-malformed embed (a missing required sub-field from a
            // backend join regression) also degrades to `nil` rather than failing
            // the whole playcut over a cosmetic enrichment. `decodeIfPresent` only
            // swallows absent/null — not malformed-present — so the outer `try?`
            // catches the throw, mirroring the `onAir` degrade-don't-throw
            // discipline in `FlowsheetResponse.init(from:)`.
            self.upcomingShow = (try? container.decodeIfPresent(Concert.self, forKey: .upcomingShow)) ?? nil
            // Same degrade-don't-throw discipline as `upcomingShow` above, but
            // per-item rather than per-field: `CriticReview`'s own Codable is
            // strict (its `url` is a non-optional `URL`), so decoding straight
            // into `[CriticReview]?` would let one malformed review fail this
            // whole playcut decode. Decoding through the tolerant wrapper first
            // and dropping `nil`s keeps a single bad review from doing that.
            let reviewItems = (try? container.decodeIfPresent([TolerantCriticReviewItem].self, forKey: .criticReviews)) ?? nil
            let reviews = reviewItems?.compactMap(\.review) ?? []
            self.criticReviews = reviews.isEmpty ? nil : reviews
            // Forward-compat with unrecognized future enum values: an unknown raw
            // string degrades to `nil` rather than failing the whole playcut decode,
            // mirroring `FlowsheetEntry.metadataStatus`'s tolerance.
            self.metadataStatus = (try? container.decodeIfPresent(MetadataStatus.self, forKey: .metadataStatus)) ?? nil
            // Additive and nullable, exactly like the fields above — absent on
            // every real feed today (see the property's doc comment), decoded
            // here so the render gate is ready once Backend wires it.
            self.discogsUnavailable = try container.decodeIfPresent(Bool.self, forKey: .discogsUnavailable)
            self.discogsUnavailableNote = try container.decodeIfPresent(String.self, forKey: .discogsUnavailableNote)
        } catch {
            ErrorReporting.shared.report(error, context: "Playcut init", category: .network)
            throw error
        }
    }
}

public struct Playlist: Codable, Sendable {
    public let playcuts: [Playcut]
    let breakpoints: [Breakpoint]
    let talksets: [Talkset]
    public let showMarkers: [ShowMarker]

    /// Who the backend reports is on the air, as a tri-state signal.
    ///
    /// Distinct from ``onAirSignOn``, which is derived from the fetched
    /// `showMarkers` and drives timeline de-duplication. `onAir` comes straight
    /// from the backend's `on_air` field and is what the on-air banner reads, so
    /// the banner is correct even when the current show's sign-on marker falls
    /// outside the fetched entry window. Defaults to ``OnAir/unknown`` (v1, older
    /// backends, cached playlists that predate the field).
    public let onAir: OnAir

    public init(
        playcuts: [Playcut],
        breakpoints: [Breakpoint],
        talksets: [Talkset],
        showMarkers: [ShowMarker] = [],
        onAir: OnAir = .unknown
    ) {
        self.playcuts = playcuts
        self.breakpoints = breakpoints
        self.talksets = talksets
        self.showMarkers = showMarkers
        self.onAir = onAir
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.playcuts = try container.decode([Playcut].self, forKey: .playcuts)
        self.breakpoints = try container.decode([Breakpoint].self, forKey: .breakpoints)
        self.talksets = try container.decode([Talkset].self, forKey: .talksets)
        // showMarkers is optional for backwards compatibility with v1 API
        self.showMarkers = try container.decodeIfPresent([ShowMarker].self, forKey: .showMarkers) ?? []
        // onAir is optional for backwards compatibility with the v1 API and with
        // cached playlists written before the field existed.
        self.onAir = try container.decodeIfPresent(OnAir.self, forKey: .onAir) ?? .unknown
    }

    private enum CodingKeys: String, CodingKey {
        case playcuts, breakpoints, talksets, showMarkers, onAir
    }

    public static let empty = Playlist(playcuts: [], breakpoints: [], talksets: [], showMarkers: [])
    
    // Compares full entry content, not just identifiers — metadata enrichment
    // (artwork, streaming links, etc.) lands on existing rows, so an ID-only
    // check would let enriched playlists slip past PlaylistService's broadcast
    // gate as unchanged. See #266.
    public static func ==(lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.playcuts == rhs.playcuts
            && lhs.breakpoints == rhs.breakpoints
            && lhs.talksets == rhs.talksets
            && lhs.showMarkers == rhs.showMarkers
            && lhs.onAir == rhs.onAir
    }

    public static func !=(lhs: Playlist, rhs: Playlist) -> Bool {
        !(lhs == rhs)
    }
}

/// Newest-first order over a heterogeneous timeline, reversing
/// ``PlaylistEntry/sortKey``.
///
/// `any PlaylistEntry` is heterogeneous (a Playcut alongside a Talkset, say),
/// so it can't lean on `PlaylistEntry`'s own `Comparable` conformance — a
/// `Self` requirement, not expressible across mixed concrete types in one
/// existential array. It reads the same `sortKey` that conformance does, so
/// there is still only one statement of the rule; see `<`'s doc comment for
/// why a duplicate `chronOrderID` is reachable, and for the one case `id`
/// doesn't resolve.
private func isOrderedNewestFirst(_ lhs: any PlaylistEntry, _ rhs: any PlaylistEntry) -> Bool {
    lhs.sortKey > rhs.sortKey
}

public extension Playlist {
    var entries: [any PlaylistEntry] {
        let playlist: [any PlaylistEntry] = (playcuts + breakpoints + talksets + showMarkers)
        return playlist.sorted(by: isOrderedNewestFirst)
    }

    /// The playcut at the head of the timeline — the newest packed row by the
    /// same `(chronOrderID, id)` order ``entries`` uses, unless a bare-keyed
    /// row postdates the entire packed partition.
    ///
    /// Every now-playing surface reads this rather than `playcuts.first`: the
    /// `playcuts` array carries wire order plus live-insert appends
    /// (`PlaylistService.upsertPlaycut`), so its head is not the newest row.
    /// While `chronOrderID` was the flowsheet `id` the two happened to
    /// coincide; keying order on the composite `(show_id, play_order)` (#839)
    /// means a dj-site reorder can move the timeline's head without touching
    /// the array's, and the lock screen, the watch, and the timeline would
    /// then name different songs.
    ///
    /// A plain `max()` has a failure the feed's sink-to-bottom fallback
    /// deliberately accepts but this reader must not: a row whose key fell
    /// back to the bare `id` (see
    /// `FlowsheetConverter.chronOrderID(showID:playOrder:id:)`) ranks below
    /// every packed row, so during a stretch of NULL-`show_id` rows `max()`
    /// would keep naming the previous show's last packed track. Row ids are
    /// global insertion serials, so the two partitions are compared by
    /// recency instead: when the newest bare row postdates every packed row,
    /// the feed has moved past the packed show and that row is the current
    /// song; otherwise the packed partition is live and its play-order head
    /// wins. An all-bare playlist (v1 payloads, a feed that dropped
    /// `show_id` wholesale, a pre-#839 cache) reduces to the pre-#839
    /// newest-id rule.
    var currentPlaycut: Playcut? {
        // The fallback key IS the row id, and a packed key can't collide with
        // one until ids reach 2^32, so `chronOrderID == id` identifies every
        // bare-keyed row (v2 fallback, v1 payloads, pre-#839 cache rows).
        let bare = playcuts.filter { $0.chronOrderID == $0.id }
        let packed = playcuts.filter { $0.chronOrderID != $0.id }
        guard let packedHead = packed.max() else { return bare.max() }
        // Bare keys equal ids, so `max()` over the bare partition is max-id.
        guard let bareHead = bare.max(),
              let newestPackedID = packed.map(\.id).max(),
              bareHead.id > newestPackedID
        else { return packedHead }
        return bareHead
    }

    /// True when the playlist carries no timeline content, ignoring `onAir`.
    ///
    /// The empty-data guard in `PlaylistService` uses this rather than `== .empty`
    /// so a content-empty fetch is still recognized as the degenerate/error case
    /// even though it now always carries an `onAir` value that would make it
    /// `!= .empty`. Otherwise a transient empty response could clear the visible
    /// feed down to a bare banner.
    var isContentEmpty: Bool {
        playcuts.isEmpty && breakpoints.isEmpty && talksets.isEmpty && showMarkers.isEmpty
    }

    /// The show marker for the DJ currently on the air, if any.
    ///
    /// Returns the last *logged* show marker — highest `id`, the insertion
    /// serial — but only when it is a sign-on. When the last marker is a
    /// sign-off (nobody is on the air) or there are no markers, returns nil.
    /// This is the marker promoted to the dedicated "on air" banner.
    ///
    /// Deliberately NOT the `(chronOrderID, id)` display order ``entries``
    /// uses: who is on the air is a question about the marker log's event
    /// order, which the display key does not carry. Two shapes invert it —
    /// a sign-off whose `play_order` is 0 (the webhook writes
    /// `sequenceWithinShow ?? 0`) packs *below* its own show's sign-on, which
    /// would strand the departed DJ on the banner; and a marker whose
    /// `show_id` is NULL takes the bare-`id` fallback key and ranks below
    /// every packed one, which would hide the DJ actually on the air behind
    /// the previous show's sign-off. Insertion order is immune to both, and
    /// to dj-site reorders, which move display position without changing who
    /// signed on last.
    var onAirSignOn: ShowMarker? {
        guard let latest = showMarkers.max(by: { $0.id < $1.id }), latest.isStart else { return nil }
        return latest
    }

    /// ``entries`` with every sign-on removed, leaving sign-offs as the only
    /// show markers in the timeline.
    ///
    /// Who is on the air is the header's job. It reads ``Playlist/onAir``
    /// straight from the backend, so it is right even when the current show's
    /// sign-on falls outside the fetched window — which is most of the time, at
    /// a 30-row page against shows averaging around 38 entries. An inline
    /// "X signed on" row can therefore only repeat the header, or sit one row
    /// above the sign-off that already reports the same handoff.
    ///
    /// A sign-off is the row that says what nothing else can: the booth
    /// emptied, and whose show just ended. It is also load-bearing while live —
    /// 16 of 108 sampled handoffs left the booth empty for 30+ minutes (longest
    /// 3.0 hours), and throughout those ``onAirSignOn`` is nil and the header
    /// has no DJ to name.
    ///
    /// Every row stays attributable without sign-ons, because each surviving
    /// marker labels the block *below* it: newest-first, a sign-off closes the
    /// show whose entries follow underneath, and the header covers the current
    /// DJ, whose entries sit above the topmost sign-off.
    ///
    /// The rule is a pure function of `isStart` — deliberately, where the
    /// previous one consulted ``onAirSignOn``. A marker's visibility now
    /// changes only when the marker does, not when the backend's notion of
    /// who is live moves underneath it.
    ///
    /// Ordering needs no special handling: Backend stamps a sign-off with its
    /// show's last `play_order`, which the packed `(show_id, play_order)` key
    /// carries into the newest-first order ``entries`` imposes, so the marker
    /// heads the block it closes. Two shapes put it lower — rows logged after
    /// the DJ signed off (4 of 108 shows sampled over 12 days), where the feed
    /// is reporting the flowsheet as logged; and the `play_order`-0 sign-off
    /// the tubafrenzy webhook can write (`sequenceWithinShow ?? 0`), which
    /// sinks to the foot of its own show. The second is absent from that
    /// sample and goes away with the webhook (WXYC/wiki#88 Phase 6a), so it is
    /// left to mis-place one row rather than given machinery of its own.
    var timelineEntries: [any PlaylistEntry] {
        entries.filter { entry in
            guard let marker = entry as? ShowMarker else { return true }
            return !marker.isStart
        }
    }
}
