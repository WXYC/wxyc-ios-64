//
//  FlowsheetContractParityTests.swift
//  Playlist
//
//  Contract-drift guard for the V2 flowsheet track row (#412 Phase 2 / #600).
//  The runtime decoder (`FlowsheetEntry` / `FlowsheetResponse`) is deliberately
//  hand-written for degrade-don't-throw tolerance and is NOT replaced by the
//  generated `WXYCAPIModels.FlowsheetV2TrackEntry` (see the rationale on
//  `FlowsheetEntry`). Instead, the generated per-variant struct is decoded
//  alongside the app's struct here so an upstream track-entry field that is
//  added / renamed / retyped surfaces as a test failure a human must triage,
//  without narrowing the runtime decoder's tolerance.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Concerts
import WXYCAPIModels
@testable import Playlist

// MARK: - V2 flowsheet codegen parity / drift guard (#600)

/// Guards the V2 flowsheet track contract against upstream drift.
///
/// Why a contract test and not a runtime type swap: `api.yaml` models a
/// flowsheet entry as a polymorphic `oneOf` family, while the app decodes every
/// variant into one flat, tolerant ``FlowsheetEntry`` (tri-state `on_air` by key
/// presence, ``TolerantConcert`` for a malformed `upcoming_show`,
/// forward-compatible ``FlowsheetEntry/metadataStatus``, `entry_type`→`message`
/// fallback). Swapping in the plain-`Codable` generated
/// ``WXYCAPIModels/FlowsheetV2TrackEntry`` would make a malformed embed *throw*
/// and freeze now-playing — the #229 class of bug. So the generated struct rides
/// along in the test target only: it is the machine-checked mirror of the wire
/// contract, and the drift guard below fails the moment the two disagree.
@Suite("Flowsheet V2 codegen parity (#600)")
struct FlowsheetContractParityTests {

    /// `id` of the fully-populated track row in `flowsheet-v2-sample.json` — the
    /// one row that carries every field ``WXYCAPIModels/FlowsheetV2TrackEntry``
    /// declares, so the parity decode exercises them all.
    private static let fullyPopulatedTrackID = 5194731

    /// Every wire field name ``WXYCAPIModels/FlowsheetV2TrackEntry`` declares that
    /// the app decodes onto ``FlowsheetEntry`` (and, in most cases, projects onto
    /// `Playcut` via `FlowsheetConverter`). Hand-maintained because Swift can't
    /// enumerate a `Codable` struct's coding keys at runtime — ``FlowsheetEntry``
    /// uses its synthesized `CodingKeys`, i.e. its stored-property names, so each
    /// entry here is the snake_case name of a real ``FlowsheetEntry`` property.
    private static let consumedWireFields: Set<String> = [
        "id",
        "show_id",
        "play_order",
        "add_time",
        "entry_type",
        "album_id",
        "rotation_id",
        "artist_id",
        "artist_name",
        "album_title",
        "track_title",
        "record_label",
        "request_flag",
        "artwork_url",
        "discogs_url",
        "release_year",
        "spotify_url",
        "apple_music_url",
        "youtube_music_url",
        "bandcamp_url",
        "soundcloud_url",
        "artist_bio",
        "artist_wikipedia_url",
        "metadata_status",
        "genres",
        "styles",
        "upcoming_show",
    ]

    /// Wire fields ``WXYCAPIModels/FlowsheetV2TrackEntry`` declares that the
    /// listener app intentionally does NOT decode. This is an explicit
    /// acknowledgement, not an oversight: keeping them here (rather than silently
    /// dropping them) is what lets the drift guard stay exact.
    ///
    /// - `segue` / `rotation_bin`: DJ-tooling / rotation-scheduling signals the
    ///   listener surface has no use for.
    /// - `on_streaming` / `track_position`: plausible future-adoption candidates
    ///   (a "library exclusive" badge, a track-position line) that simply aren't
    ///   built yet.
    ///
    /// Revisit — and move into `consumedWireFields` by wiring the field into
    /// ``FlowsheetEntry`` / `FlowsheetConverter` — if a feature needs one of these.
    private static let knownUnconsumedWireFields: Set<String> = [
        "segue",
        "rotation_bin",
        "on_streaming",
        "track_position",
    ]

    /// The primary drift guard. `FlowsheetV2TrackEntry.CodingKeys` is
    /// `CaseIterable`, so its raw values are the authoritative, codegen-derived
    /// set of wire fields — it changes automatically when `api.yaml` is
    /// regenerated. The right-hand side is hand-maintained. When upstream adds,
    /// renames, or removes a track-entry field, the regenerated `CodingKeys` no
    /// longer equal `consumed ∪ knownUnconsumed`, this fails, and a human decides
    /// whether to adopt the field (wire it into ``FlowsheetEntry`` and add it to
    /// `consumedWireFields`) or acknowledge it (add it to
    /// `knownUnconsumedWireFields`).
    @Test("Every generated track-entry wire field is either consumed or explicitly acknowledged")
    func generatedWireFieldsAreAccountedFor() {
        let generatedWireFields = Set(FlowsheetV2TrackEntry.CodingKeys.allCases.map(\.rawValue))

        #expect(generatedWireFields == Self.consumedWireFields.union(Self.knownUnconsumedWireFields))

        // The two hand-maintained sets must stay disjoint — a field is either
        // consumed or acknowledged-unconsumed, never both.
        #expect(Self.consumedWireFields.isDisjoint(with: Self.knownUnconsumedWireFields))
    }

    /// Complementary to the field-name guard: proves the same golden JSON row
    /// decodes on BOTH the generated struct and the app's tolerant struct, which
    /// catches a type mismatch (e.g. a field that changed `String` → `Int`) the
    /// name-set comparison can't see. The generated struct's `add_time` / nested
    /// `starts_on` are `Date`s, so it needs a matching date strategy (see
    /// ``apiDateDecodingStrategy``); the app struct decodes `add_time` as a
    /// `String`, so it uses a plain decoder — mirroring the real runtime path.
    @Test("Both the generated and the app struct decode the fully-populated fixture row")
    func bothStructsDecodeTheFullyPopulatedRow() throws {
        let rowData = try Self.fullyPopulatedTrackRowData()

        // Generated struct — strict; a missing required field or a type mismatch
        // (including inside the embedded `upcoming_show` Concert) throws here.
        let apiDecoder = JSONDecoder()
        apiDecoder.dateDecodingStrategy = Self.apiDateDecodingStrategy
        let generated = try apiDecoder.decode(FlowsheetV2TrackEntry.self, from: rowData)

        #expect(generated.id == Self.fullyPopulatedTrackID)
        #expect(generated.entryType == .track)
        #expect(generated.artistName == "Jessica Pratt")
        #expect(generated.metadataStatus == .enrichedMatch)
        #expect(generated.rotationBin == .h)
        #expect(generated.upcomingShow?.headliningArtistRaw == "Jessica Pratt")

        // App struct — the tolerant runtime decoder, unchanged.
        let appEntry = try JSONDecoder().decode(FlowsheetEntry.self, from: rowData)

        #expect(appEntry.id == Self.fullyPopulatedTrackID)
        #expect(appEntry.entry_type == "track")
        #expect(appEntry.artist_name == "Jessica Pratt")
    }

    /// Backs the `consumedWireFields` claim: decoding the fully-populated row must
    /// actually populate ``FlowsheetEntry`` (and the projected `Playcut`) from the
    /// wire, so `consumedWireFields` can't quietly list a field the app never
    /// reads. Spot-checks a representative field from each decode path (raw
    /// scalars, arrays, the tolerant metadata accessor, and the embedded concert).
    @Test("The app struct actually reads the fields it claims to consume")
    func appStructConsumesTheClaimedFields() throws {
        let rowData = try Self.fullyPopulatedTrackRowData()
        let entry = try JSONDecoder().decode(FlowsheetEntry.self, from: rowData)

        #expect(entry.artist_id == 812)
        #expect(entry.album_id == 660123)
        #expect(entry.rotation_id == 4471)
        #expect(entry.release_year == 2015)
        #expect(entry.request_flag == true)
        #expect(entry.artwork_url == "https://example.com/artwork/back-baby.jpg")
        #expect(entry.artist_bio == "Jessica Pratt is an American singer-songwriter from Los Angeles.")
        #expect(entry.genres == ["Rock"])
        #expect(entry.styles == ["Folk, World, & Country"])
        #expect(entry.metadataStatus == .enrichedMatch)
        #expect(entry.upcoming_show?.concert?.headliningArtistRaw == "Jessica Pratt")

        // And the converter projects them onto the Playcut.
        let playlist = FlowsheetConverter.convert([entry])
        let playcut = try #require(playlist.playcuts.first)
        #expect(playcut.artistId == 812)
        #expect(playcut.genres == ["Rock"])
        #expect(playcut.upcomingShow?.headliningArtistRaw == "Jessica Pratt")
    }

    // MARK: - Date strategy

    /// Replicates the vendored infrastructure's date handling for decoding the
    /// generated `Date` fields (`add_time`, and the embedded concert's
    /// `starts_on` / `starts_at` / `doors_at`). `WXYCAPIModels.CodableHelper`
    /// decodes with `OpenISO8601DateFormatter`, whose `init()` is `internal` and
    /// so unreachable from this module — so we mirror its exact three-format
    /// fallback chain (fractional-second instant → whole-second instant →
    /// date-only) with plain, fixed-locale formatters.
    private static let apiDateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let raw = try decoder.singleValueContainer().decode(String.self)
        for formatter in [isoFractional, isoWholeSecond, isoDateOnly] {
            if let date = formatter.date(from: raw) { return date }
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unparseable date: \(raw)")
        )
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private static let isoFractional = makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ")
    private static let isoWholeSecond = makeFormatter("yyyy-MM-dd'T'HH:mm:ssZZZZZ")
    private static let isoDateOnly = makeFormatter("yyyy-MM-dd")

    // MARK: - Fixture helpers

    /// Extracts the single fully-populated track row from `flowsheet-v2-sample.json`
    /// as its own JSON payload, so it can be decoded directly as a per-variant
    /// entry. The fixture's `entries` array is heterogeneous (talkset /
    /// breakpoint / show markers), and `FlowsheetV2TrackEntry` requires
    /// `entry_type == "track"` and a non-optional `request_flag`, so the array
    /// can't be decoded as `[FlowsheetV2TrackEntry]` wholesale — we pull the one
    /// track row out by `id`.
    private static func fullyPopulatedTrackRowData() throws -> Data {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "flowsheet-v2-sample",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
        let data = try Data(contentsOf: fixtureURL)
        let top = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(top["entries"] as? [[String: Any]])
        let trackRow = try #require(entries.first { ($0["id"] as? Int) == fullyPopulatedTrackID })
        return try JSONSerialization.data(withJSONObject: trackRow)
    }
}
