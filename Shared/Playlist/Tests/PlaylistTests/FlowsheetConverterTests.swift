//
//  FlowsheetConverterTests.swift
//  Playlist
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

// MARK: - FlowsheetConverter Tests

@Suite("FlowsheetConverter Tests")
struct FlowsheetConverterTests {

    @Test("Converts playcut entry correctly when message is nil")
    func convertsPlaycutEntry() {
        let entry = FlowsheetEntry(
            id: 123,
            show_id: 456,
            album_id: 789,
            artist_name: "Test Artist",
            album_title: "Test Album",
            track_title: "Test Song",
            record_label: "Test Label",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 1,
            add_time: "2024-01-15T14:30:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.playcuts.count == 1)
        #expect(playlist.breakpoints.isEmpty)
        #expect(playlist.talksets.isEmpty)
        #expect(playlist.showMarkers.isEmpty)

        let playcut = playlist.playcuts.first!
        #expect(playcut.id == 123)
        #expect(playcut.artistName == "Test Artist")
        #expect(playcut.songTitle == "Test Song")
        #expect(playcut.releaseTitle == "Test Album")
        #expect(playcut.labelName == "Test Label")
        #expect(playcut.chronOrderID == 123)
    }

    @Test("Converts talkset entry correctly when message is 'Talkset'")
    func convertsTalksetEntry() {
        let entry = FlowsheetEntry(
            id: 124,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: "Talkset",
            play_order: 2,
            add_time: "2024-01-15T14:35:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.talksets.count == 1)
        #expect(playlist.playcuts.isEmpty)
        #expect(playlist.breakpoints.isEmpty)
        #expect(playlist.showMarkers.isEmpty)

        let talkset = playlist.talksets.first!
        #expect(talkset.id == 124)
        #expect(talkset.chronOrderID == 124)
    }

    @Test("Converts breakpoint entry correctly when message contains 'Breakpoint'")
    func convertsBreakpointEntry() {
        let entry = FlowsheetEntry(
            id: 125,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: "01:00 PM Breakpoint",
            play_order: 3,
            add_time: "2024-01-15T15:00:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.breakpoints.count == 1)
        #expect(playlist.playcuts.isEmpty)
        #expect(playlist.talksets.isEmpty)
        #expect(playlist.showMarkers.isEmpty)

        let breakpoint = playlist.breakpoints.first!
        #expect(breakpoint.id == 125)
        #expect(breakpoint.chronOrderID == 125)
    }

    @Test("Converts show start marker correctly")
    func convertsShowStartMarker() {
        let entry = FlowsheetEntry(
            id: 126,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: "Start of Show: DJ Cool joined the set at 10/14/2025 2:00 PM",
            play_order: 4,
            add_time: "2024-01-15T14:00:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.showMarkers.count == 1)
        #expect(playlist.playcuts.isEmpty)
        #expect(playlist.breakpoints.isEmpty)
        #expect(playlist.talksets.isEmpty)

        let marker = playlist.showMarkers.first!
        #expect(marker.id == 126)
        #expect(marker.isStart == true)
        #expect(marker.djName == "DJ Cool")
        #expect(marker.chronOrderID == 126)
    }

    @Test("Converts show end marker correctly")
    func convertsShowEndMarker() {
        let entry = FlowsheetEntry(
            id: 127,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: "End of Show: DJ Cool left the set at 10/14/2025 4:00 PM",
            play_order: 5,
            add_time: "2024-01-15T16:00:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.showMarkers.count == 1)

        let marker = playlist.showMarkers.first!
        #expect(marker.id == 127)
        #expect(marker.isStart == false)
        #expect(marker.djName == "DJ Cool")
    }

    @Test("Handles missing artist and track title gracefully")
    func handlesMissingArtistAndTrack() {
        let entry = FlowsheetEntry(
            id: 128,
            show_id: nil,
            album_id: nil,
            artist_name: nil,
            album_title: nil,
            track_title: nil,
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: nil,
            play_order: 6,
            add_time: "2024-01-15T14:00:00.000Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.playcuts.count == 1)
        let playcut = playlist.playcuts.first!
        #expect(playcut.artistName == "Unknown")
        #expect(playcut.songTitle == "Unknown")
    }

    @Test("Parses ISO 8601 timestamp with fractional seconds correctly")
    func parsesTimestampWithFractionalSeconds() {
        let entry = FlowsheetEntry(
            id: 129,
            show_id: nil,
            album_id: nil,
            artist_name: "Artist",
            album_title: nil,
            track_title: "Song",
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: nil,
            play_order: 1,
            add_time: "2024-01-15T14:30:45.123Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        let playcut = playlist.playcuts.first!
        // 2024-01-15T14:30:45.123Z = 1705329045123 milliseconds (approximately)
        #expect(playcut.hour > 0)
    }

    @Test("Parses ISO 8601 timestamp without fractional seconds correctly")
    func parsesTimestampWithoutFractionalSeconds() {
        let entry = FlowsheetEntry(
            id: 130,
            show_id: nil,
            album_id: nil,
            artist_name: "Artist",
            album_title: nil,
            track_title: "Song",
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: nil,
            play_order: 1,
            add_time: "2024-01-15T14:30:45Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        let playcut = playlist.playcuts.first!
        #expect(playcut.hour > 0)
    }

    @Test("Decodes HTML entities in artist and track names")
    func decodesHTMLEntities() {
        let entry = FlowsheetEntry(
            id: 200,
            show_id: nil,
            album_id: nil,
            artist_name: "Raphael Rogi&#324;ski &amp; Ruzi&#269;njak Tajni",
            album_title: "Test &lt;Album&gt;",
            track_title: "Test &#8217;Song&#8217;",
            record_label: "Label &quot;Name&quot;",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: nil,
            message: nil,
            play_order: 1,
            add_time: "2024-01-15T14:00:00Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.playcuts.count == 1)
        let playcut = playlist.playcuts.first!
        #expect(playcut.artistName == "Raphael Rogiński & Ruzičnjak Tajni")
        #expect(playcut.releaseTitle == "Test <Album>")
        #expect(playcut.songTitle == "Test \u{2019}Song\u{2019}")
        #expect(playcut.labelName == "Label \"Name\"")
    }

    @Test("Converts multiple entries of different types")
    func convertsMultipleEntryTypes() {
        let entries = [
            FlowsheetEntry(
                id: 1, show_id: nil, album_id: nil,
                artist_name: "Artist", album_title: "Album", track_title: "Song",
                record_label: "Label", rotation_id: nil, rotation_play_freq: nil,
                request_flag: nil, message: nil, play_order: 1,
                add_time: "2024-01-15T14:00:00Z"
            ),
            FlowsheetEntry(
                id: 2, show_id: nil, album_id: nil,
                artist_name: nil, album_title: nil, track_title: nil,
                record_label: nil, rotation_id: nil, rotation_play_freq: nil,
                request_flag: nil, message: "Talkset", play_order: 2,
                add_time: "2024-01-15T14:05:00Z"
            ),
            FlowsheetEntry(
                id: 3, show_id: nil, album_id: nil,
                artist_name: nil, album_title: nil, track_title: nil,
                record_label: nil, rotation_id: nil, rotation_play_freq: nil,
                request_flag: nil, message: "2:00 PM Breakpoint", play_order: 3,
                add_time: "2024-01-15T14:10:00Z"
            ),
            FlowsheetEntry(
                id: 4, show_id: nil, album_id: nil,
                artist_name: nil, album_title: nil, track_title: nil,
                record_label: nil, rotation_id: nil, rotation_play_freq: nil,
                request_flag: nil, message: "Start of Show: DJ Test joined the set at 10/14/2025",
                play_order: 4, add_time: "2024-01-15T14:15:00Z"
            )
        ]

        let playlist = FlowsheetConverter.convert(entries)

        #expect(playlist.playcuts.count == 1)
        #expect(playlist.talksets.count == 1)
        #expect(playlist.breakpoints.count == 1)
        #expect(playlist.showMarkers.count == 1)
    }

    // MARK: - V2 API response format

    @Test("Decodes and converts V2 API response with entry_type field")
    func decodesV2ResponseWrapper() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "flowsheet-v2-sample",
            withExtension: "json",
            subdirectory: "Fixtures"
        )!
        let data = try Data(contentsOf: fixtureURL)

        let response = try JSONDecoder().decode(FlowsheetResponse.self, from: data)
        let playlist = FlowsheetConverter.convert(response.entries)

        #expect(playlist.playcuts.count == 1)
        #expect(playlist.talksets.count == 1)
        #expect(playlist.breakpoints.count == 1)
        #expect(playlist.showMarkers.count == 2)

        let playcut = try #require(playlist.playcuts.first)
        #expect(playcut.artistName == "Miyako Koda")
        #expect(playcut.songTitle == "Sleep in Peace")
        #expect(playcut.releaseTitle == "in the shadow of Jupiter")
        #expect(playcut.labelName == "Grandisc")

        let showStart = try #require(playlist.showMarkers.first { $0.isStart })
        #expect(showStart.djName == "DJ Moonbeam")

        let showEnd = try #require(playlist.showMarkers.first { !$0.isStart })
        #expect(showEnd.djName == "DJ Moonbeam")
    }

    @Test("Converts V2 talkset with nil message using entry_type")
    func convertsV2TalksetWithNilMessage() {
        let entry = FlowsheetEntry(
            id: 100, show_id: nil, album_id: nil,
            artist_name: nil, album_title: nil, track_title: nil,
            record_label: nil, rotation_id: nil, rotation_play_freq: nil,
            request_flag: nil, message: nil, play_order: 1,
            add_time: "2026-04-17T22:00:00Z", entry_type: "talkset"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.talksets.count == 1)
        #expect(playlist.playcuts.isEmpty)
    }

    @Test("Converts V2 breakpoint with nil message using entry_type")
    func convertsV2BreakpointWithNilMessage() {
        let entry = FlowsheetEntry(
            id: 101, show_id: nil, album_id: nil,
            artist_name: nil, album_title: nil, track_title: nil,
            record_label: nil, rotation_id: nil, rotation_play_freq: nil,
            request_flag: nil, message: nil, play_order: 2,
            add_time: "2026-04-17T22:00:00Z", entry_type: "breakpoint"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.breakpoints.count == 1)
        #expect(playlist.playcuts.isEmpty)
    }

    // MARK: - Inline genres/styles (#402)

    @Test("Decodes inline genres/styles from a V2 entry onto the Playcut")
    func decodesInlineGenresAndStyles() throws {
        let json = """
        {
            "id": 402,
            "show_id": 1947064,
            "album_id": 789,
            "artist_name": "Juana Molina",
            "album_title": "DOGA",
            "track_title": "la paradoja",
            "record_label": "Sonamos",
            "rotation_id": null,
            "rotation_play_freq": null,
            "request_flag": false,
            "message": null,
            "play_order": 1,
            "add_time": "2026-05-15T01:45:59.058Z",
            "entry_type": "track",
            "genres": ["Rock"],
            "styles": ["Folk, World, & Country"]
        }
        """
        let entry = try JSONDecoder().decode(FlowsheetEntry.self, from: Data(json.utf8))
        #expect(entry.genres == ["Rock"])
        #expect(entry.styles == ["Folk, World, & Country"])

        let playlist = FlowsheetConverter.convert([entry])
        let playcut = try #require(playlist.playcuts.first)
        #expect(playcut.genres == ["Rock"])
        #expect(playcut.styles == ["Folk, World, & Country"])
    }

    @Test("Inline genres/styles are absent when the V2 entry omits them")
    func inlineGenresAndStylesAbsentWhenOmitted() {
        let entry = FlowsheetEntry(
            id: 403, show_id: nil, album_id: nil,
            artist_name: "Chuquimamani-Condori", album_title: "Edits",
            track_title: "Call Your Name", record_label: nil,
            rotation_id: nil, rotation_play_freq: nil,
            request_flag: false, message: nil, play_order: 1,
            add_time: "2026-05-15T01:45:59.058Z", entry_type: "track"
        )

        let playlist = FlowsheetConverter.convert([entry])
        let playcut = playlist.playcuts.first!
        #expect(playcut.genres == nil)
        #expect(playcut.styles == nil)
    }

    // MARK: - Breakpoint radio_hour (ios#404)

    @Test("Breakpoint hour comes from radio_hour (exact top-of-hour); timeCreated keeps add_time")
    func breakpointUsesRadioHourWhenPresent() throws {
        // `add_time` is the logging instant (~1 min before the hour); `radio_hour`
        // is the exact top-of-hour the chip should display.
        let entry = FlowsheetEntry(
            id: 300, show_id: nil, album_id: nil,
            artist_name: nil, album_title: nil, track_title: nil,
            record_label: nil, rotation_id: nil, rotation_play_freq: nil,
            request_flag: nil, message: nil, play_order: 1,
            add_time: "2024-01-15T15:58:42Z",
            entry_type: "breakpoint",
            radio_hour: "2024-01-15T16:00:00Z"
        )

        let playlist = FlowsheetConverter.convert([entry])
        let breakpoint = try #require(playlist.breakpoints.first)

        let expectedHour = UInt64(try Date("2024-01-15T16:00:00Z", strategy: .iso8601).timeIntervalSince1970 * 1000)
        let expectedCreated = UInt64(try Date("2024-01-15T15:58:42Z", strategy: .iso8601).timeIntervalSince1970 * 1000)
        #expect(breakpoint.hour == expectedHour)
        #expect(breakpoint.timeCreated == expectedCreated)
    }

    @Test("Breakpoint hour falls back to add_time when radio_hour is absent")
    func breakpointFallsBackToAddTimeWhenRadioHourMissing() throws {
        // Older servers omit `radio_hour`; the chip must still render from add_time.
        let entry = FlowsheetEntry(
            id: 301, show_id: nil, album_id: nil,
            artist_name: nil, album_title: nil, track_title: nil,
            record_label: nil, rotation_id: nil, rotation_play_freq: nil,
            request_flag: nil, message: nil, play_order: 1,
            add_time: "2024-01-15T15:58:42Z",
            entry_type: "breakpoint"
        )

        let playlist = FlowsheetConverter.convert([entry])
        let breakpoint = try #require(playlist.breakpoints.first)

        let expectedAddTime = UInt64(try Date("2024-01-15T15:58:42Z", strategy: .iso8601).timeIntervalSince1970 * 1000)
        #expect(breakpoint.hour == expectedAddTime)
        #expect(breakpoint.timeCreated == expectedAddTime)
    }

    @Test("Breakpoint hour falls back to add_time when radio_hour is present but unparseable")
    func breakpointFallsBackToAddTimeWhenRadioHourMalformed() throws {
        // A server that emits a malformed/unrecognized `radio_hour` must be no
        // worse than one that omits it: the chip falls back to `add_time`, never
        // to the current wall-clock time.
        let entry = FlowsheetEntry(
            id: 302, show_id: nil, album_id: nil,
            artist_name: nil, album_title: nil, track_title: nil,
            record_label: nil, rotation_id: nil, rotation_play_freq: nil,
            request_flag: nil, message: nil, play_order: 1,
            add_time: "2024-01-15T15:58:42Z",
            entry_type: "breakpoint",
            radio_hour: "not-a-date"
        )

        let playlist = FlowsheetConverter.convert([entry])
        let breakpoint = try #require(playlist.breakpoints.first)

        let expectedAddTime = UInt64(try Date("2024-01-15T15:58:42Z", strategy: .iso8601).timeIntervalSince1970 * 1000)
        #expect(breakpoint.hour == expectedAddTime)
        #expect(breakpoint.timeCreated == expectedAddTime)
    }

    @Test("Breakpoint hour falls back to add_time when radio_hour is an empty string")
    func breakpointFallsBackToAddTimeWhenRadioHourEmpty() throws {
        let entry = FlowsheetEntry(
            id: 303, show_id: nil, album_id: nil,
            artist_name: nil, album_title: nil, track_title: nil,
            record_label: nil, rotation_id: nil, rotation_play_freq: nil,
            request_flag: nil, message: nil, play_order: 1,
            add_time: "2024-01-15T15:58:42Z",
            entry_type: "breakpoint",
            radio_hour: ""
        )

        let playlist = FlowsheetConverter.convert([entry])
        let breakpoint = try #require(playlist.breakpoints.first)

        let expectedAddTime = UInt64(try Date("2024-01-15T15:58:42Z", strategy: .iso8601).timeIntervalSince1970 * 1000)
        #expect(breakpoint.hour == expectedAddTime)
        #expect(breakpoint.timeCreated == expectedAddTime)
    }

    // MARK: - Cross-show ordering (regression test for #265)

    @Test("Sorts entries chronologically across shows when play_order resets")
    func sortsEntriesChronologicallyAcrossShows() throws {
        // A fetch can include the tail of a previous show alongside the head of
        // the current show. `play_order` resets to 1 at the start of every show,
        // so the previous show's tail has high play_orders and the current
        // show's head has low play_orders. The Postgres `id` is strictly
        // monotonic across all shows, so the freshly-inserted current-show
        // entry has the higher id. `Playlist.entries` must rank by a globally
        // monotonic key, otherwise the UI shows the previous show's tail as
        // "Now Playing".
        let entries = [
            // Current show — freshly inserted, low play_order, high id
            FlowsheetEntry(
                id: 5210394, show_id: 1947064, album_id: nil,
                artist_name: "Tortoise", album_title: "Standards",
                track_title: "The Lithium Stiffs", record_label: "Thrill Jockey Records",
                rotation_id: nil, rotation_play_freq: nil,
                request_flag: false, message: nil,
                play_order: 7, add_time: "2026-05-15T01:45:59.058Z",
                entry_type: "track"
            ),
            // Previous show — already finished, high play_order, lower id
            FlowsheetEntry(
                id: 5210353, show_id: 1947063, album_id: nil,
                artist_name: "Luomo", album_title: "Vocalcity",
                track_title: "Tessio", record_label: "Force Tracks",
                rotation_id: nil, rotation_play_freq: nil,
                request_flag: false, message: nil,
                play_order: 34, add_time: "2026-05-14T21:57:00.000Z",
                entry_type: "track"
            )
        ]

        let playlist = FlowsheetConverter.convert(entries)

        #expect(playlist.playcuts.count == 2)

        let sorted = playlist.entries
        #expect(sorted.count == 2)
        #expect(sorted[0].id == 5210394, "current show's fresh entry must rank first")
        #expect(sorted[1].id == 5210353, "previous show's older entry must rank second")
    }
}
