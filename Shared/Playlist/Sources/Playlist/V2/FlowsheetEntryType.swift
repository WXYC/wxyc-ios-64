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
import Logger

/// Represents the type of a flowsheet entry, determined from the `entry_type` field
/// with a fallback to the legacy `message`-based heuristic.
///
/// Every case here renders as timeline content. Rows that don't — guest-DJ
/// `dj_join`/`dj_leave` markers, freeform `message` rows, and any `entry_type`
/// this build doesn't recognize — have no case; `from(_:)` returns `nil` for
/// them instead, and ``FlowsheetConverter`` drops the row rather than minting
/// a case for it. This "no case renders nothing" invariant is specific to the
/// `entry_type` path: the legacy `from(message:)` fallback below intentionally
/// keeps its always-render-as-playcut default, since a nil/unrecognized
/// `message` on a pre-`entry_type` (v1-shaped) row is, by that format's
/// semantics, a track.
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
    ///   content a listener surface should render (see the `dj_join`/`dj_leave`,
    ///   `message`, and `default` cases below).
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
            case "message":
                // Backend-Service's transformToV2 emits this today for freeform
                // DJ messages that aren't a pre-classified "Talkset"/"Breakpoint"
                // text — a live contract variant (see
                // WXYCAPIModels.FlowsheetEntryType.message /
                // FlowsheetV2MessageEntry), not a future addition. This is a
                // DELIBERATE drop: the listener app has no rendering surface for
                // freeform messages, and routing a "message" row through
                // `from(message:)` would resurrect #693-style "Unknown / Unknown"
                // cards, since that fallback's own default mints `.playcut` for
                // text it doesn't recognize — which a genuinely freeform message
                // never will.
                return nil
            default:
                // An `entry_type` this build genuinely doesn't recognize yet — a
                // future server addition, distinct from the known-but-unrendered
                // "message" case above. Dropping is the safe default: minting
                // `.playcut` here is what produced the #693 "Unknown / Unknown"
                // cards for dj_join/dj_leave before they got their own cases, and
                // any future non-track marker type is more likely to look like
                // that than like a song play. Logged (unlike the designed-drop
                // cases above) because an unrecognized value is itself signal —
                // either a contract addition this build hasn't caught up to, or a
                // server-side bug — worth surfacing without spamming every poll
                // for a marker type this build already knows to expect and drop.
                Log(.warning, category: .network, "Unrecognized flowsheet entry_type '\(entryType)' on entry \(entry.id); dropping row")
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
