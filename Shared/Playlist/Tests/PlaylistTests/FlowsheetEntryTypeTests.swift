//
//  FlowsheetEntryTypeTests.swift
//  Playlist
//
//  Tests for FlowsheetEntryType parsing.
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

// MARK: - FlowsheetEntryType Tests

@Suite("FlowsheetEntryType Tests")
struct FlowsheetEntryTypeTests {

    @Test("Nil message returns playcut")
    func nilMessageIsPlaycut() {
        let entryType = FlowsheetEntryType.from(message: nil)
        #expect(entryType == .playcut)
    }

    @Test("Empty message returns playcut")
    func emptyMessageIsPlaycut() {
        // Empty message should be treated as unknown, defaulting to playcut
        let entryType = FlowsheetEntryType.from(message: "")
        #expect(entryType == .playcut)
    }

    @Test("'Talkset' message returns talkset")
    func talksetMessage() {
        let entryType = FlowsheetEntryType.from(message: "Talkset")
        #expect(entryType == .talkset)
    }

    @Test("Message containing 'Breakpoint' returns breakpoint")
    func breakpointMessage() {
        let entryType = FlowsheetEntryType.from(message: "01:00 PM Breakpoint")
        #expect(entryType == .breakpoint)
    }

    @Test("Plain 'Breakpoint' returns breakpoint")
    func plainBreakpointMessage() {
        let entryType = FlowsheetEntryType.from(message: "Breakpoint")
        #expect(entryType == .breakpoint)
    }

    @Test("'Start of Show:' parses DJ name correctly")
    func showStartWithDJName() {
        let entryType = FlowsheetEntryType.from(message: "Start of Show: DJ Cool joined the set at 10/14/2025 2:00 PM")
        if case .showStart(let djName) = entryType {
            #expect(djName == "DJ Cool")
        } else {
            Issue.record("Expected showStart but got \(entryType)")
        }
    }

    @Test("'End of Show:' parses DJ name correctly")
    func showEndWithDJName() {
        let entryType = FlowsheetEntryType.from(message: "End of Show: DJ Cool left the set at 10/14/2025 4:00 PM")
        if case .showEnd(let djName) = entryType {
            #expect(djName == "DJ Cool")
        } else {
            Issue.record("Expected showEnd but got \(entryType)")
        }
    }

    @Test("'Start of Show:' with no space before 'joined' falls back to full text")
    func showStartWithNoSpaceBeforeJoined() {
        // When there's no space before "joined", the pattern doesn't match
        // and the full text is returned as the DJ name fallback
        let entryType = FlowsheetEntryType.from(message: "Start of Show: joined the set at 10/14/2025")
        if case .showStart(let djName) = entryType {
            #expect(djName == "joined the set at 10/14/2025")
        } else {
            Issue.record("Expected showStart but got \(entryType)")
        }
    }

    @Test("'Start of Show:' without standard format falls back")
    func showStartWithoutStandardFormat() {
        let entryType = FlowsheetEntryType.from(message: "Start of Show: Some Random Text")
        if case .showStart(let djName) = entryType {
            // Should return the entire text after "Start of Show:" since it doesn't match pattern
            #expect(djName == "Some Random Text")
        } else {
            Issue.record("Expected showStart but got \(entryType)")
        }
    }

    @Test("Unknown message defaults to playcut")
    func unknownMessageDefaultsToPlaycut() {
        let entryType = FlowsheetEntryType.from(message: "Some random message")
        #expect(entryType == .playcut)
    }

    @Test("Case sensitivity: 'TALKSET' is not talkset")
    func caseSensitiveTalkset() {
        let entryType = FlowsheetEntryType.from(message: "TALKSET")
        // Should be playcut since exact match "Talkset" is expected
        #expect(entryType == .playcut)
    }

    @Test("Case sensitivity: 'breakpoint' still contains 'Breakpoint'")
    func caseSensitiveBreakpoint() {
        // "breakpoint" does NOT contain "Breakpoint" (case sensitive)
        let entryType = FlowsheetEntryType.from(message: "breakpoint")
        #expect(entryType == .playcut)
    }

    // MARK: - entry_type field detection (v2 API)

    @Test("entry_type 'track' returns playcut")
    func entryTypeTrackIsPlaycut() {
        let entry = FlowsheetEntry(
            id: 1, show_id: nil, album_id: nil, artist_name: "Autechre",
            album_title: "Confield", track_title: "VI Scose Poise",
            record_label: "Warp", rotation_id: nil, rotation_play_freq: nil,
            request_flag: false, message: nil, play_order: 1,
            add_time: "2026-04-17T22:00:00Z", entry_type: "track"
        )
        #expect(FlowsheetEntryType.from(entry) == .playcut)
    }

    @Test("entry_type 'talkset' returns talkset even when message is nil")
    func entryTypeTalksetWithNilMessage() {
        let entry = FlowsheetEntry(
            id: 2, show_id: nil, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 2, add_time: "2026-04-17T22:05:00Z",
            entry_type: "talkset"
        )
        #expect(FlowsheetEntryType.from(entry) == .talkset)
    }

    @Test("entry_type 'breakpoint' returns breakpoint even when message is nil")
    func entryTypeBreakpointWithNilMessage() {
        let entry = FlowsheetEntry(
            id: 3, show_id: nil, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 3, add_time: "2026-04-17T22:10:00Z",
            entry_type: "breakpoint"
        )
        #expect(FlowsheetEntryType.from(entry) == .breakpoint)
    }

    @Test("entry_type 'show_start' returns showStart with dj_name")
    func entryTypeShowStart() {
        let entry = FlowsheetEntry(
            id: 4, show_id: nil, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 4, add_time: "2026-04-17T20:00:00Z",
            entry_type: "show_start", dj_name: "DJ Moonbeam"
        )
        #expect(FlowsheetEntryType.from(entry) == .showStart(djName: "DJ Moonbeam"))
    }

    @Test("entry_type 'show_end' returns showEnd with dj_name")
    func entryTypeShowEnd() {
        let entry = FlowsheetEntry(
            id: 5, show_id: nil, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 5, add_time: "2026-04-17T23:00:00Z",
            entry_type: "show_end", dj_name: "DJ Moonbeam"
        )
        #expect(FlowsheetEntryType.from(entry) == .showEnd(djName: "DJ Moonbeam"))
    }

    @Test("entry_type 'show_start' with empty dj_name returns nil djName")
    func entryTypeShowStartEmptyDJName() {
        let entry = FlowsheetEntry(
            id: 6, show_id: nil, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 6, add_time: "2026-04-17T20:00:00Z",
            entry_type: "show_start", dj_name: ""
        )
        #expect(FlowsheetEntryType.from(entry) == .showStart(djName: nil))
    }

    @Test("Falls back to message-based detection when entry_type is nil")
    func fallsBackToMessageDetection() {
        let entry = FlowsheetEntry(
            id: 7, show_id: nil, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: "Talkset", play_order: 7, add_time: "2026-04-17T22:00:00Z"
        )
        #expect(FlowsheetEntryType.from(entry) == .talkset)
    }
}
