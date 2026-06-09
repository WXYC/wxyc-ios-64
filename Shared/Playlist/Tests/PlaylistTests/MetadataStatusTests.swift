//
//  MetadataStatusTests.swift
//  Playlist
//
//  Decoder tests for the v2 `metadata_status` wire field and the
//  `MetadataStatus` enum it maps to. Predecessor work for #270.
//
//  Created by Jake Bromberg on 05/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Playlist

@Suite("MetadataStatus")
struct MetadataStatusTests {

    // MARK: - Enum raw values

    @Test("Maps each known raw value to its enum case", arguments: [
        ("pending", MetadataStatus.pending),
        ("enriching", MetadataStatus.enriching),
        ("enriched_match", MetadataStatus.enrichedMatch),
        ("enriched_no_match", MetadataStatus.enrichedNoMatch),
        ("failed_no_retry", MetadataStatus.failedNoRetry),
    ])
    func mapsKnownRawValues(raw: String, expected: MetadataStatus) {
        #expect(MetadataStatus(rawValue: raw) == expected)
    }

    @Test("Returns nil for an unrecognized raw value (forward-compat)")
    func returnsNilForUnknownRawValue() {
        #expect(MetadataStatus(rawValue: "newly_invented_state") == nil)
        #expect(MetadataStatus(rawValue: "") == nil)
        #expect(MetadataStatus(rawValue: "PENDING") == nil) // case-sensitive
    }

    // MARK: - FlowsheetEntry decoding

    @Test("Decodes each known metadata_status value from JSON", arguments: [
        ("pending", MetadataStatus.pending),
        ("enriching", MetadataStatus.enriching),
        ("enriched_match", MetadataStatus.enrichedMatch),
        ("enriched_no_match", MetadataStatus.enrichedNoMatch),
        ("failed_no_retry", MetadataStatus.failedNoRetry),
    ])
    func decodesFlowsheetEntryMetadataStatus(raw: String, expected: MetadataStatus) throws {
        let json = """
        {
            "id": 1,
            "play_order": 1,
            "add_time": "2026-04-17T22:53:48.500Z",
            "entry_type": "track",
            "metadata_status": "\(raw)"
        }
        """
        let entry = try JSONDecoder().decode(FlowsheetEntry.self, from: Data(json.utf8))
        #expect(entry.metadataStatus == expected)
        #expect(entry.metadata_status == raw)
    }

    @Test("Decodes FlowsheetEntry with absent metadata_status field as nil")
    func decodesAbsentFieldAsNil() throws {
        let json = """
        {
            "id": 2,
            "play_order": 2,
            "add_time": "2026-04-17T22:53:48.500Z",
            "entry_type": "track"
        }
        """
        let entry = try JSONDecoder().decode(FlowsheetEntry.self, from: Data(json.utf8))
        #expect(entry.metadata_status == nil)
        #expect(entry.metadataStatus == nil)
    }

    @Test("Decodes unknown metadata_status string as nil (forward-compat)")
    func decodesUnknownStringAsNilForwardCompat() throws {
        // A future Backend enum extension reaches an older iOS build. The row
        // must still decode; the consumer falls back to the proxy-fetch path
        // for `nil`-status rows, which is the safe default.
        let json = """
        {
            "id": 3,
            "play_order": 3,
            "add_time": "2026-04-17T22:53:48.500Z",
            "entry_type": "track",
            "metadata_status": "newly_invented_state"
        }
        """
        let entry = try JSONDecoder().decode(FlowsheetEntry.self, from: Data(json.utf8))
        // Raw string is preserved (for diagnostics), but the typed accessor is nil.
        #expect(entry.metadata_status == "newly_invented_state")
        #expect(entry.metadataStatus == nil)
    }

    @Test("Decodes canonical-example v2 fixture with mixed metadata_status values")
    func decodesV2FixtureWithMetadataStatus() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "flowsheet-v2-sample",
            withExtension: "json",
            subdirectory: "Fixtures"
        )!
        let data = try Data(contentsOf: fixtureURL)
        let response = try JSONDecoder().decode(FlowsheetResponse.self, from: data)

        // The canonical examples cover the three enriched states the
        // inline-metadata branch of `PlaycutDetailView` (#270) renders directly.
        let track = response.entries.filter { $0.entry_type == "track" }
        let statuses = track.compactMap(\.metadataStatus)
        #expect(statuses.contains(.enrichedMatch))
        #expect(statuses.contains(.enrichedNoMatch))
        #expect(statuses.contains(.failedNoRetry))

        // Non-track entries (talkset, breakpoint, show_*) carry no metadata_status.
        for entry in response.entries where entry.entry_type != "track" {
            #expect(entry.metadataStatus == nil)
        }
    }
}
