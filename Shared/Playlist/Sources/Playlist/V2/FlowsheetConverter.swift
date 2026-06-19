//
//  FlowsheetConverter.swift
//  Playlist
//
//  Converts v2 API flowsheet responses to canonical Playlist model.
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Converts v2 API responses to canonical Playlist model.
enum FlowsheetConverter {

    /// Converts a list of flowsheet entries to a canonical Playlist.
    ///
    /// - Parameter entries: Raw flowsheet entries from v2 API.
    /// - Returns: A Playlist with entries sorted into appropriate arrays.
    static func convert(_ entries: [FlowsheetEntry]) -> Playlist {
        var playcuts: [Playcut] = []
        var breakpoints: [Breakpoint] = []
        var talksets: [Talkset] = []
        var showMarkers: [ShowMarker] = []

        for entry in entries {
            let entryType = FlowsheetEntryType.from(entry)
            let hour = parseHour(from: entry.add_time)
            // `play_order` resets to 1 per show, so it can't act as a global
            // chronological key — see #265. `flowsheet.id` is a Postgres serial,
            // strictly monotonic across all shows.
            let id = UInt64(entry.id)
            let chronOrderID = id

            switch entryType {
            case .playcut:
                let playcut = Playcut(
                    id: id,
                    hour: hour,
                    chronOrderID: chronOrderID,
                    timeCreated: hour,
                    songTitle: (entry.track_title ?? "Unknown").htmlDecoded,
                    labelName: entry.record_label?.htmlDecoded,
                    artistName: (entry.artist_name ?? "Unknown").htmlDecoded,
                    releaseTitle: entry.album_title?.htmlDecoded,
                    rotation: entry.rotation_id != nil,
                    artworkURL: entry.artwork_url.flatMap { URL(string: $0) },
                    discogsURL: entry.discogs_url.flatMap { URL(string: $0) },
                    releaseYear: entry.release_year,
                    spotifyURL: entry.spotify_url.flatMap { URL(string: $0) },
                    appleMusicURL: entry.apple_music_url.flatMap { URL(string: $0) },
                    youtubeMusicURL: entry.youtube_music_url.flatMap { URL(string: $0) },
                    bandcampURL: entry.bandcamp_url.flatMap { URL(string: $0) },
                    soundcloudURL: entry.soundcloud_url.flatMap { URL(string: $0) },
                    artistBio: entry.artist_bio,
                    artistWikipediaURL: entry.artist_wikipedia_url.flatMap { URL(string: $0) },
                    genres: entry.genres,
                    styles: entry.styles
                )
                playcuts.append(playcut)

            case .talkset:
                talksets.append(Talkset(id: id, hour: hour, chronOrderID: chronOrderID, timeCreated: hour))

            case .breakpoint:
                // Display the exact top-of-hour from `radio_hour` when present
                // and parseable, falling back to `add_time` for servers that
                // predate the field or send an unparseable value (ios#404).
                // `timeCreated` keeps the original logging instant.
                let breakpointHour = entry.radio_hour.flatMap { parseHourIfValid(from: $0) } ?? hour
                breakpoints.append(Breakpoint(id: id, hour: breakpointHour, chronOrderID: chronOrderID, timeCreated: hour))

            case .showStart(let djName):
                let marker = ShowMarker(
                    id: id,
                    hour: hour,
                    chronOrderID: chronOrderID,
                    timeCreated: hour,
                    isStart: true,
                    djName: djName,
                    message: entry.message ?? ""
                )
                showMarkers.append(marker)

            case .showEnd(let djName):
                let marker = ShowMarker(
                    id: id,
                    hour: hour,
                    chronOrderID: chronOrderID,
                    timeCreated: hour,
                    isStart: false,
                    djName: djName,
                    message: entry.message ?? ""
                )
                showMarkers.append(marker)
            }
        }

        return Playlist(
            playcuts: playcuts,
            breakpoints: breakpoints,
            talksets: talksets,
            showMarkers: showMarkers
        )
    }

    /// Parses an ISO 8601 timestamp string to milliseconds since 1970.
    ///
    /// - Parameter isoString: ISO 8601 formatted date string.
    /// - Returns: Milliseconds since 1970, or current time in milliseconds if parsing fails.
    ///   The current-time fallback keeps unparseable entries sorting near the
    ///   top rather than at the epoch; callers that have their own fallback
    ///   (e.g. a breakpoint's `add_time`) should use `parseHourIfValid` instead.
    private static func parseHour(from isoString: String) -> UInt64 {
        // Use current time as fallback so entries sort correctly rather than
        // appearing at epoch (Jan 1, 1970).
        parseHourIfValid(from: isoString) ?? UInt64(Date.now.timeIntervalSince1970 * 1000)
    }

    /// Parses an ISO 8601 timestamp string to milliseconds since 1970, returning
    /// `nil` when the string can't be parsed.
    ///
    /// Unlike `parseHour`, this never substitutes the current time, so a caller
    /// with its own fallback (the breakpoint chip falls back to `add_time`) can
    /// distinguish "absent or malformed" from a real instant.
    ///
    /// - Parameter isoString: ISO 8601 formatted date string.
    /// - Returns: Milliseconds since 1970, or `nil` if parsing fails or the
    ///   instant predates 1970 (see `milliseconds(since1970:)`).
    private static func parseHourIfValid(from isoString: String) -> UInt64? {
        // Use modern Swift Foundation parsing
        if let date = try? Date(isoString, strategy: .iso8601) {
            return milliseconds(since1970: date)
        }
        // Fallback: try with fractional seconds strategy
        let fractionalStrategy = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? Date(isoString, strategy: fractionalStrategy) {
            return milliseconds(since1970: date)
        }
        return nil
    }

    /// Converts a date to unsigned milliseconds since 1970, returning `nil` for a
    /// pre-1970 instant. `UInt64(_:)` traps on a negative `Double`, so a
    /// parseable-but-negative timestamp (e.g. a server bug emitting a pre-epoch
    /// `radio_hour`) must be rejected here rather than crashing the conversion.
    private static func milliseconds(since1970 date: Date) -> UInt64? {
        let ms = date.timeIntervalSince1970 * 1000
        guard ms >= 0, ms.isFinite else { return nil }
        return UInt64(ms)
    }
}
