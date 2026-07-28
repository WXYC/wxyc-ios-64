//
//  FlowsheetEntryType.swift
//  Playlist
//
//  Entry type detection for v2 flowsheet entries.
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Represents the type of a flowsheet entry, determined from the `entry_type` field
/// with a fallback to the legacy `message`-based heuristic.
///
/// Every case here renders as timeline content. Rows that don't — guest-DJ
/// `dj_join`/`dj_leave` markers and any `entry_type` this build doesn't
/// recognize — have no case; `from(_:)` returns `nil` for them instead, and
/// ``FlowsheetConverter`` drops the row rather than minting a case for it.
enum FlowsheetEntryType: Equatable, Sendable {
    case playcut
    case talkset
    case breakpoint
    case showStart(djName: String?)
    case showEnd(djName: String?)

    /// Determines the entry type from a flowsheet entry's fields.
    ///
    /// Uses `entry_type` (v2 API) as the primary signal. Falls back to the
    /// legacy `message`-based heuristic when `entry_type` is absent.
    ///
    /// - Parameter entry: A raw flowsheet entry.
    /// - Returns: The detected entry type, or `nil` when the entry carries no
    ///   content a listener surface should render (see the `dj_join`/`dj_leave`
    ///   and `default` cases below).
    static func from(_ entry: FlowsheetEntry) -> FlowsheetEntryType? {
        if let entryType = entry.entry_type {
            switch entryType {
            case "track":
                return .playcut
            case "talkset":
                return .talkset
            case "breakpoint":
                return .breakpoint
            case "show_start":
                return .showStart(djName: entry.dj_name?.nilIfEmpty)
            case "show_end":
                return .showEnd(djName: entry.dj_name?.nilIfEmpty)
            case "dj_join", "dj_leave":
                // Guest-DJ joins/leaves an in-progress show. These marker rows
                // carry only id/show_id/play_order/add_time/entry_type/dj_name —
                // no track/artist/album fields — so classifying them as `.playcut`
                // used to mint an "Unknown / Unknown" card (#693). Mirrors
                // tubafrenzy, which never surfaces these rows either.
                return nil
            default:
                // An `entry_type` this build doesn't recognize (a future server
                // addition). Dropping is the safe default: minting `.playcut` here
                // is what produced the #693 "Unknown / Unknown" cards for
                // dj_join/dj_leave before they got their own cases above, and any
                // future non-track marker type is more likely to look like that
                // than like a song play.
                return nil
            }
        }

        return from(message: entry.message)
    }

    /// Legacy entry type detection from the message field.
    ///
    /// - Parameter message: The message field from a FlowsheetEntry.
    /// - Returns: The detected entry type.
    static func from(message: String?) -> FlowsheetEntryType {
        guard let message else {
            return .playcut
        }

        if message == "Talkset" {
            return .talkset
        }

        if message.contains("Breakpoint") {
            return .breakpoint
        }

        if message.hasPrefix("Start of Show:") {
            let remainder = message.dropFirst("Start of Show:".count)
            let djName = extractDJName(from: String(remainder))
            return .showStart(djName: djName)
        }

        if message.hasPrefix("End of Show:") {
            let remainder = message.dropFirst("End of Show:".count)
            let djName = extractDJName(from: String(remainder))
            return .showEnd(djName: djName)
        }

        // Default to playcut for unknown message types
        return .playcut
    }

    /// Extracts the DJ name from the remainder of a show marker message.
    private static func extractDJName(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        // The format is typically "DJ Name joined the set at DATE" or "DJ Name left the set at DATE"
        // Extract just the DJ name part before "joined" or "left"
        if let joinedRange = trimmed.range(of: " joined the set") {
            let djPart = trimmed[..<joinedRange.lowerBound]
            let name = djPart.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        if let leftRange = trimmed.range(of: " left the set") {
            let djPart = trimmed[..<leftRange.lowerBound]
            let name = djPart.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        // Fallback: return the whole trimmed string
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
