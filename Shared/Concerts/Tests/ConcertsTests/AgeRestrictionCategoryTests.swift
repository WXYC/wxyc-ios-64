//
//  AgeRestrictionCategoryTests.swift
//  Concerts
//
//  Coverage for the free-text `age_restriction` normalizer that powers the
//  All-ages facet. The scraper hands us arbitrary phrasing ("18+", "21 PLUS",
//  "All Ages"); the parser collapses that into three filterable categories while
//  erring toward `.unknown` so a show is never hidden unless it's provably
//  restricted.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts

@Suite("AgeRestrictionCategory")
struct AgeRestrictionCategoryTests {

    /// `(rawText, expected)` pairs. Extracted to a top-level constant so the
    /// Swift Testing macro doesn't type-check a large inline tuple literal
    /// (a known "unable to type-check in reasonable time" trigger).
    static let cases: [(String?, AgeRestrictionCategory)] = [
        // nil / empty / whitespace → unknown (no phrasing to interpret)
        (nil, .unknown),
        ("", .unknown),
        ("   ", .unknown),

        // all-ages phrasings (case-insensitive, whitespace-collapsed)
        ("All Ages", .allAges),
        ("all ages", .allAges),
        ("ALL AGES", .allAges),
        ("  All   Ages  ", .allAges),
        ("All Ages (bar with ID)", .allAges),
        ("AA", .allAges),
        ("aa", .allAges),

        // restricted phrasings → the leading integer is the minimum age
        ("18+", .restricted(minAge: 18)),
        ("21+", .restricted(minAge: 21)),
        ("21 PLUS", .restricted(minAge: 21)),
        ("18 plus", .restricted(minAge: 18)),
        ("18 and up", .restricted(minAge: 18)),
        ("21 and over", .restricted(minAge: 21)),
        ("  18+  ", .restricted(minAge: 18)),

        // unrecognized → unknown (surfaced via a debug log in development)
        ("Ask venue", .unknown),
        ("Sold out", .unknown),
        // A venue name that merely contains the letters "aa" must NOT be read
        // as the "AA" all-ages token.
        ("Saxapahaw", .unknown),
        // A bare integer with no recognized suffix is ambiguous → unknown.
        ("18", .unknown),
    ]

    @Test("Maps raw age-restriction text to a category", arguments: cases)
    func mapsRawText(_ rawText: String?, _ expected: AgeRestrictionCategory) {
        #expect(AgeRestrictionCategory(rawText: rawText) == expected)
    }
}
