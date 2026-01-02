//
//  FlowsheetEntryType.swift
//  Playlist
//
//  Entry type detection for v2 flowsheet entries.
//

import Foundation

/// Represents the type of a flowsheet entry, determined by parsing the `message` field.
enum FlowsheetEntryType: Equatable, Sendable {
    case playcut
    case talkset
    case breakpoint
    case showStart(djName: String?)
    case showEnd(djName: String?)

    /// Determines the entry type from the message field.
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
