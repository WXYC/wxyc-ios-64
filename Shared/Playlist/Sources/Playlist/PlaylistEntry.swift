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

import Foundation
import Logger

extension URL {
    static let WXYCPlaylist = URL(string: "http://wxyc.info/playlists/recentEntries?v=2&n=50")!
#if WXYC_320_STREAM_ENABLED
    static let WXYCStream320kMP3 = URL(string: "https://audio-mp3.ibiblio.org:8000/wxyc-alt.mp3")!
#endif
}

extension TimeZone {
    /// The station's broadcast time zone. WXYC broadcasts from Chapel Hill, NC
    /// (US Eastern). The `?? .gmt` fallback is unreachable for this fixed,
    /// always-known identifier but keeps the declaration force-unwrap-free.
    static let wxycStation = TimeZone(identifier: "America/New_York") ?? .gmt
}

public protocol PlaylistEntry: Codable, Identifiable, Sendable, Equatable, Hashable, Comparable {
    var id: UInt64 { get }
    var hour: UInt64 { get }
    var chronOrderID: UInt64 { get }
    var timeCreated: UInt64 { get }
}

public extension PlaylistEntry {
    static func <(lhs: Self, rhs: Self) -> Bool {
        lhs.chronOrderID < rhs.chronOrderID
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
        self.id = try container.decode(UInt64.self, forKey: .id)
        self.hour = try container.decode(UInt64.self, forKey: .hour)
        self.chronOrderID = try container.decode(UInt64.self, forKey: .chronOrderID)
        self.timeCreated = try container.decodeIfPresent(UInt64.self, forKey: .timeCreated) ?? container.decode(UInt64.self, forKey: .hour)
    }

    private enum CodingKeys: String, CodingKey {
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
        let date = Date(timeIntervalSince1970: Double(hour) / 1000)
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
        self.id = try container.decode(UInt64.self, forKey: .id)
        self.hour = try container.decode(UInt64.self, forKey: .hour)
        self.chronOrderID = try container.decode(UInt64.self, forKey: .chronOrderID)
        self.timeCreated = try container.decodeIfPresent(UInt64.self, forKey: .timeCreated) ?? container.decode(UInt64.self, forKey: .hour)
    }

    private enum CodingKeys: String, CodingKey {
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
        self.id = try container.decode(UInt64.self, forKey: .id)
        self.hour = try container.decode(UInt64.self, forKey: .hour)
        self.chronOrderID = try container.decode(UInt64.self, forKey: .chronOrderID)
        self.timeCreated = try container.decodeIfPresent(UInt64.self, forKey: .timeCreated) ?? container.decode(UInt64.self, forKey: .hour)
        self.isStart = try container.decode(Bool.self, forKey: .isStart)
        self.djName = try container.decodeIfPresent(String.self, forKey: .djName)
        self.message = try container.decode(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
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

    /// Whether this playcut carries inline metadata from the v2 flowsheet API.
    public var hasV2Metadata: Bool {
        artworkURL != nil || discogsURL != nil || spotifyURL != nil
    }

    private enum CodingKeys: String, CodingKey {
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
        styles: [String]? = nil
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UInt64.self, forKey: .id)
        self.hour = try container.decode(UInt64.self, forKey: .hour)
        self.chronOrderID = try container.decode(UInt64.self, forKey: .chronOrderID)
        self.timeCreated = try container.decodeIfPresent(UInt64.self, forKey: .timeCreated) ?? container.decode(UInt64.self, forKey: .hour)

        do {
            self.songTitle = try container.decode(String.self, forKey: .songTitle).htmlDecoded
            self.labelName = try container.decodeIfPresent(String.self, forKey: .labelName)?.htmlDecoded
            self.artistName = try container.decode(String.self, forKey: .artistName).htmlDecoded
            self.releaseTitle = try container.decodeIfPresent(String.self, forKey: .releaseTitle)?.htmlDecoded

            // V1 API returns rotation as a string ("true"/"false"), V2 converter uses Bool
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
        } catch {
            ErrorReporting.shared.report(error, context: "Playcut init", category: .network)
            throw error
        }
    }
}

public extension Playcut {
    /// Cache key for artwork lookups based on artist and release/song title.
    ///
    /// Uses `releaseTitle` if available and non-empty, otherwise falls back to `songTitle`.
    /// This ensures consistent cache keys regardless of whether `releaseTitle` is `nil` or empty string.
    var artworkCacheKey: String {
        let release = releaseTitle.flatMap { $0.isEmpty ? nil : $0 } ?? songTitle
        return "\(artistName)-\(release)"
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

public extension Playlist {
    var entries: [any PlaylistEntry] {
        let playlist: [any PlaylistEntry] = (playcuts + breakpoints + talksets + showMarkers)
        return playlist.sorted { $0.chronOrderID > $1.chronOrderID }
    }

    /// The show marker for the DJ currently on the air, if any.
    ///
    /// Returns the most recent show marker — highest `chronOrderID`, which the API
    /// assigns in chronological order — but only when it is a sign-on. When the latest
    /// marker is a sign-off (nobody is on the air) or there are no markers, returns nil.
    /// This is the marker promoted to the dedicated "on air" banner.
    var onAirSignOn: ShowMarker? {
        guard let latest = showMarkers.max(by: { $0.chronOrderID < $1.chronOrderID }),
              latest.isStart else { return nil }
        return latest
    }

    /// `entries` filtered down to the show markers worth showing inline.
    ///
    /// Sign-offs are dropped entirely — a DJ leaving the air isn't an event listeners need
    /// in the feed. Earlier sign-ons remain as show boundaries. The current DJ's sign-on is
    /// also dropped, since it is promoted to its own "on air" banner above the list.
    var timelineEntries: [any PlaylistEntry] {
        let onAirID = onAirSignOn?.id
        return entries.filter { entry in
            guard let marker = entry as? ShowMarker else { return true }
            return marker.isStart && marker.id != onAirID
        }
    }
}
