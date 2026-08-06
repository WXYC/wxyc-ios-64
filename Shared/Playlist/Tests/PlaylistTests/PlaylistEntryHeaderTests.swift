//
//  PlaylistEntryHeaderTests.swift
//  Playlist
//
//  Tests for PlaylistEntryHeader, the shared id/hour/chronOrderID/timeCreated
//  decode block factored out of Breakpoint/Talkset/ShowMarker/Playcut so the
//  four-line block (plus the timeCreated ?? hour back-compat fallback) is
//  written once instead of four times (#769).
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

/// Minimal `Decodable` wrapper exercising `PlaylistEntryHeader` directly,
/// independent of any one `PlaylistEntry` conformer.
private struct HeaderOnlyFixture: Decodable {
    let header: PlaylistEntryHeader

    enum CodingKeys: String, CodingKey, PlaylistEntryCodingKeys {
        case id, hour, chronOrderID, timeCreated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        header = try PlaylistEntryHeader(from: container)
    }
}

@Suite("PlaylistEntryHeader Tests")
struct PlaylistEntryHeaderTests {
    @Test("Decodes id, hour, chronOrderID, and timeCreated when all are present")
    func decodesAllFields() throws {
        let json = #"{"id":1,"hour":1000,"chronOrderID":2,"timeCreated":3000}"#
        let fixture = try JSONDecoder().decode(HeaderOnlyFixture.self, from: Data(json.utf8))
        #expect(fixture.header.id == 1)
        #expect(fixture.header.hour == 1000)
        #expect(fixture.header.chronOrderID == 2)
        #expect(fixture.header.timeCreated == 3000)
    }

    @Test("Falls back to hour when timeCreated is absent (feeds that predate the field)")
    func fallsBackToHourWhenTimeCreatedAbsent() throws {
        let json = #"{"id":1,"hour":1000,"chronOrderID":2}"#
        let fixture = try JSONDecoder().decode(HeaderOnlyFixture.self, from: Data(json.utf8))
        #expect(fixture.header.timeCreated == fixture.header.hour)
        #expect(fixture.header.timeCreated == 1000)
    }

    @Test("Throws when a required header field is missing")
    func throwsWhenRequiredFieldMissing() {
        let json = #"{"hour":1000,"chronOrderID":2}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HeaderOnlyFixture.self, from: Data(json.utf8))
        }
    }
}
