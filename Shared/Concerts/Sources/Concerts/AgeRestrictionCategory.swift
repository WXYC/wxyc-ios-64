//
//  AgeRestrictionCategory.swift
//  Concerts
//
//  Normalizes the backend's free-text `age_restriction` string into a small
//  filterable category for the On Tour "All ages" facet. The scraper emits
//  arbitrary phrasing ("18+", "21 PLUS", "All Ages", "AA"); this collapses it to
//  three cases while deliberately erring toward `.unknown` — the All-ages filter
//  hides only shows we can *prove* are restricted, so an unrecognized phrasing
//  stays visible rather than being wrongly suppressed.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger

/// A concert's age policy, normalized from the free-text `age_restriction` field.
///
/// The raw string is retained on ``Concert/ageRestriction`` for display; this
/// type exists only to drive the All-ages predicate. Parsing is case-insensitive
/// and whitespace-collapsed, and conservative: anything the parser can't confidently
/// classify becomes ``unknown`` (logged in development so new scraper phrasings
/// surface) rather than a guessed restriction.
public enum AgeRestrictionCategory: Sendable, Equatable {

    /// No policy given, or a phrasing the parser doesn't recognize. Never hidden
    /// by the All-ages filter (we can't prove it's restricted).
    case unknown

    /// An explicitly all-ages show ("All Ages", "AA").
    case allAges

    /// An age-restricted show; `minAge` is the leading integer from the source
    /// ("18+" → 18, "21 and up" → 21).
    case restricted(minAge: Int)

    /// Recognized "or older" suffixes that, following a leading integer, mark a
    /// restriction. Kept intentionally tight — a missed phrasing degrades to
    /// ``unknown`` (safe: the show stays visible), while a false match would
    /// wrongly hide an all-ages show.
    private static let restrictionSuffixes = ["+", "plus", "and up", "and over"]

    /// Classifies a raw `age_restriction` string.
    ///
    /// - Parameter rawText: The backend's `age_restriction`, or `nil`.
    public init(rawText: String?) {
        guard let collapsed = Self.collapseWhitespace(rawText), !collapsed.isEmpty else {
            self = .unknown
            return
        }
        let normalized = collapsed.lowercased()

        // All-ages: the distinctive phrase anywhere, or a standalone "AA" token
        // (token-matched, not substring-matched, so "Saxapahaw" can't trip it).
        if normalized.contains("all ages") || Self.tokens(normalized).contains("aa") {
            self = .allAges
            return
        }

        if let minAge = Self.leadingRestrictedAge(normalized) {
            // A leading age of 0 ("0+", "0 and up") sets no minimum — that's
            // all-ages, not a restriction. Treating it as `.restricted(minAge: 0)`
            // would wrongly hide the show behind the All-ages filter.
            self = minAge > 0 ? .restricted(minAge: minAge) : .allAges
            return
        }

        // Non-empty but unrecognized: stay visible, but log so a new phrasing is
        // noticed during development rather than silently mis-filtered.
        Log(.debug, category: .general, "AgeRestrictionCategory: unrecognized age_restriction \"\(collapsed)\"")
        self = .unknown
    }

    /// Trims and collapses runs of internal whitespace to single spaces, or `nil`
    /// for a `nil` input.
    private static func collapseWhitespace(_ text: String?) -> String? {
        text?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Splits normalized text into alphanumeric tokens for word-boundary matching.
    private static func tokens(_ normalized: String) -> [Substring] {
        normalized.split { !$0.isLetter && !$0.isNumber }
    }

    /// Parses a leading integer plus a recognized "or older" suffix from
    /// already-normalized text, returning the minimum age, or `nil` when the
    /// shape doesn't match (including a bare integer with no suffix).
    private static func leadingRestrictedAge(_ normalized: String) -> Int? {
        let digits = normalized.prefix { $0.isNumber }
        guard !digits.isEmpty, let age = Int(digits) else { return nil }
        let remainder = normalized
            .dropFirst(digits.count)
            .trimmingCharacters(in: .whitespaces)
        return restrictionSuffixes.contains(where: remainder.hasPrefix) ? age : nil
    }
}
