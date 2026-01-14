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
            let entryType = FlowsheetEntryType.from(message: entry.message)
            let hour = parseHour(from: entry.add_time)
            let chronOrderID = UInt64(entry.play_order)
            let id = UInt64(entry.id)

            switch entryType {
            case .playcut:
                let playcut = Playcut(
                    id: id,
                    hour: hour,
                    chronOrderID: chronOrderID,
                    songTitle: (entry.track_title ?? "Unknown").htmlDecoded,
                    labelName: entry.record_label?.htmlDecoded,
                    artistName: (entry.artist_name ?? "Unknown").htmlDecoded,
                    releaseTitle: entry.album_title?.htmlDecoded,
                    rotation: entry.rotation_id != nil
                )
                playcuts.append(playcut)

            case .talkset:
                talksets.append(Talkset(id: id, hour: hour, chronOrderID: chronOrderID))

            case .breakpoint:
                breakpoints.append(Breakpoint(id: id, hour: hour, chronOrderID: chronOrderID))

            case .showStart(let djName):
                let marker = ShowMarker(
                    id: id,
                    hour: hour,
                    chronOrderID: chronOrderID,
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
    /// - Returns: Milliseconds since 1970, or 0 if parsing fails.
    private static func parseHour(from isoString: String) -> UInt64 {
        // Use modern Swift Foundation parsing
        if let date = try? Date(isoString, strategy: .iso8601) {
            return UInt64(date.timeIntervalSince1970 * 1000)
        }
        // Fallback: try with fractional seconds strategy
        let fractionalStrategy = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? Date(isoString, strategy: fractionalStrategy) {
            return UInt64(date.timeIntervalSince1970 * 1000)
        }
        return 0
    }
}
