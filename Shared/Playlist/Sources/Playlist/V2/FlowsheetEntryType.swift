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
    /// - Returns: The detected entry type.
    static func from(_ entry: FlowsheetEntry) -> FlowsheetEntryType {
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
            default:
                return .playcut
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
