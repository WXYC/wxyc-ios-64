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
//  `representativeName(in:)` picks a display-worthy original-cased name out
//  of a group of playcuts that all share one `normalizedEntityKey` — issue
//  #646. It was originally a private helper on
//  `SpotlightDonationService.donateArtists` (#640/#644), which only fixed
//  artist display casing on the donation path; `ArtistEntityQuery.entities(for:)`
//  (the resolution path AppIntents calls to materialize an entity from a
//  persisted id) had the same "displays the lowercased dedup key" defect.
//  Hoisting the selection rule here lets both paths share one implementation
//  instead of agreeing by convention.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist

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

/// Picks a representative original-cased artist name from `group` — a set of
/// playcuts that all normalize to the same `normalizedEntityKey` — for
/// display purposes (`ArtistEntity.displayName`). Ranked by how often each
/// exact raw `Playcut.artistName` string recurs in `group` (so a clean
/// "Stereolab" outvotes a rarer "STEREOLAB" typo or a "Stereolab feat. …"
/// variant), ties broken by whichever raw string appears first in `group`'s
/// order. Shared by `ArtistEntityQuery.entities(for:)` and
/// `SpotlightDonationService.donateArtists` so the resolution and donation
/// paths agree on what a deduped artist group displays (#646). `group` is
/// expected to be non-empty at both call sites — it comes from
/// `Dictionary(grouping:)`, which never produces an empty value array — but
/// this falls back to `""` rather than trapping if ever called with an empty
/// group.
public func representativeName(in group: [Playcut]) -> String {
    var counts: [String: Int] = [:]
    var order: [String] = []
    for playcut in group {
        let name = playcut.artistName
        if counts[name] == nil {
            order.append(name)
        }
        counts[name, default: 0] += 1
    }

    guard var representative = order.first else { return "" }
    var representativeCount = counts[representative, default: 0]
    for name in order.dropFirst() {
        let count = counts[name, default: 0]
        if count > representativeCount {
            representative = name
            representativeCount = count
        }
    }
    return representative
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
