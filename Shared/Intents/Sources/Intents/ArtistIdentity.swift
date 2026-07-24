//
//  ArtistIdentity.swift
//  Intents
//
//  Shared conventions for every F5x string-keyed AppEntity (ArtistEntity today;
//  ReleaseEntity/LabelEntity etc. in sibling tickets reuse these two helpers
//  rather than inventing ad-hoc normalization or hashing per entity type).
//
//  `normalizedEntityKey` collapses name variations ("Stereolab" vs "Stereolab
//  feat. Nurse With Wound") down to one dedup key. `stableEntityID` turns that
//  key into a `UInt64` suitable for `EntityID<Owner>`. Swift's `String.hashValue`
//  is randomized per process launch (hash-seed randomization for DoS
//  resistance) and must never be used here — AppEntity identifiers have to be
//  stable across app launches so Siri/Spotlight can round-trip a previously
//  indexed or donated identifier.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Lowercases, trims, collapses internal whitespace, and strips a trailing
/// "feat. …" / "featuring …" clause so name variations of the same artist
/// (or other string-keyed entity) dedup to a single normalized key.
public func normalizedEntityKey(_ rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutFeature = trimmed.range(
        of: #"\s+feat(uring|\.)?\s+.*$"#,
        options: [.regularExpression, .caseInsensitive]
    ).map { String(trimmed[trimmed.startIndex..<$0.lowerBound]) } ?? trimmed
    let collapsedWhitespace = withoutFeature
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    return collapsedWhitespace.lowercased()
}

/// FNV-1a 64-bit hash of `key`, used to derive a stable `UInt64` for
/// string-keyed entities. Deterministic across process launches and platforms
/// — unlike `String.hashValue`, which is randomized per launch and would
/// break "ids stable across launches" for any entity backed by a string key
/// rather than a model id.
public func stableEntityID(for key: String) -> UInt64 {
    let fnvOffsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    let fnvPrime: UInt64 = 0x0000_0100_0000_01B3
    var hash = fnvOffsetBasis
    for byte in key.utf8 {
        hash ^= UInt64(byte)
        hash = hash.multipliedReportingOverflow(by: fnvPrime).partialValue
    }
    return hash
}
