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
    /// - Parameters:
    ///   - entries: Raw flowsheet entries from v2 API.
    ///   - onAir: The backend's tri-state on-air signal, carried through to the
    ///     resulting ``Playlist``. Defaults to ``OnAir/unknown`` for callers that
    ///     have no on-air information (e.g. entry-only test fixtures).
    /// - Returns: A Playlist with entries sorted into appropriate arrays.
    static func convert(_ entries: [FlowsheetEntry], onAir: OnAir = .unknown) -> Playlist {
        var playcuts: [Playcut] = []
        var breakpoints: [Breakpoint] = []
        var talksets: [Talkset] = []
        var showMarkers: [ShowMarker] = []

        for entry in entries {
            // `nil` means the row carries no renderable content — a dj_join/
            // dj_leave marker or an unrecognized future `entry_type` (#693) —
            // so it's dropped entirely: no playcut, no marker, no downstream
            // artwork lookup or Spotlight donation (both are driven off the
            // `playcuts` array built below).
            guard let entryType = FlowsheetEntryType.from(entry) else { continue }
            let hour = parseHour(from: entry.add_time)
            let id = UInt64(entry.id)
            let chronOrderID = Self.chronOrderID(showID: entry.show_id, playOrder: entry.play_order, id: entry.id)

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
                    styles: entry.styles,
                    artistId: entry.artist_id,
                    upcomingShow: entry.upcoming_show?.concert,
                    criticReviews: entry.criticReviews,
                    metadataStatus: entry.metadataStatus
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
            showMarkers: showMarkers,
            onAir: onAir
        )
    }

    /// Derives the timeline's sort key from the composite `(show_id, play_order)`,
    /// packed into a single `UInt64` as `show_id << 32 | play_order` — a
    /// bijection at today's magnitudes (`show_id` ~1.95e6 packs to ~8.4e15,
    /// roughly 2000x inside `UInt64`, so no boundary test is needed; contrast a
    /// decimal `K = 1000` multiplier, which has only ~20x headroom over the
    /// observed max `play_order` of 50 in a 3-hour show and would fail
    /// *silently* on breach).
    ///
    /// `show_id` is a Backend-Service serial — confirmed strictly monotone
    /// against `id` and `add_time` in a live sample — so it orders shows
    /// against each other and dominates the packed key; `play_order` orders
    /// entries within a show *and reflects dj-site reorders*
    /// (`changeOrder`), unlike the old `id`-only key, which could never see
    /// one (WXYC/wxyc-ios-64#839). #265's cross-show ordering fix survives
    /// unchanged: a higher `show_id` always outranks a lower one regardless
    /// of either show's `play_order` values.
    ///
    /// `id` remains row *identity* everywhere else (`Playcut.id`, `ForEach`
    /// keys) — this key is ordering-only, and duplicate composite keys are
    /// reachable: a `changeOrder` reorder shifts a contiguous `play_order`
    /// range in one transaction, but only the enriched subset of that range
    /// broadcasts over `live-fs-topic`, so the app can transiently hold a
    /// pre-reorder and a post-reorder row that both claim the same
    /// `(show_id, play_order)`. Callers must add `id` as an explicit tiebreak
    /// when sorting — see `Playlist.entries` and `PlaylistEntry`'s
    /// `Comparable` conformance — since this key alone is not always unique.
    ///
    /// - Parameters:
    ///   - showID: The row's `show_id`. `nil` only on decoder tolerance for a
    ///     malformed/legacy row: Backend-Service itself 500s on a nil
    ///     `show_id` in `changeOrder`, and every row in a live 200-row sample
    ///     carried one post-#693, so this is not a real-traffic path. Falls
    ///     back to `UInt64(id) << 32` rather than the raw `id`: a bare
    ///     `UInt64(id)` (~5e6) would be dwarfed by a real packed key (~8e15)
    ///     and sink to the very bottom of the feed — the exact collapse this
    ///     ticket exists to fix — whereas shifting `id` the same way real
    ///     keys are shifted keeps the row visible near its true
    ///     chronological position. `id` grows faster than `show_id` (many
    ///     rows per show), so this sentinel lands slightly *above* the row's
    ///     true position rather than below it — the same "float to now,
    ///     don't sink to the epoch" bias `parseHour`'s own fallback already
    ///     uses for an unparseable `add_time`. This rule is a pure function
    ///     of the one row, so it produces an identical key whether the row
    ///     arrives via the REST `/flowsheet` batch or a single-entry
    ///     `live-fs-topic` SSE frame (`LiveFsEvent` -> `convert([entry])`),
    ///     which has no neighbouring rows to borrow a show from.
    ///   - playOrder: The row's `play_order` within its show.
    ///   - id: The row's Postgres serial id — used verbatim as identity
    ///     elsewhere, and as the nil-`show_id` sentinel's high bits here.
    static func chronOrderID(showID: Int?, playOrder: Int, id: Int) -> UInt64 {
        guard let showID else {
            return UInt64(id) << 32
        }
        return (UInt64(showID) << 32) | UInt64(playOrder)
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
