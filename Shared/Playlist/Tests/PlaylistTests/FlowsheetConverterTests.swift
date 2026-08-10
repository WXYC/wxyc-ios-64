//
//  FlowsheetConverterTests.swift
//  Playlist
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Concerts
import ConcertsTesting
@testable import Playlist

// MARK: - FlowsheetConverter Tests

@Suite("FlowsheetConverter Tests")
struct FlowsheetConverterTests {

    // MARK: - Embedded upcoming_show (#473)

    @Test("Carries the embedded upcoming_show through to the playcut")
    func carriesUpcomingShow() {
        let entry = FlowsheetEntry(
            id: 123,
            show_id: 456,
            album_id: nil,
            artist_name: "Jessica Pratt",
            album_title: "On Your Own Love Again",
            track_title: "Back, Baby",
            record_label: "Drag City",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 1,
            add_time: "2026-04-17T22:53:48.500Z",
            upcoming_show: TolerantConcert(concert: .stub(status: .soldOut))
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.playcuts.count == 1)
        #expect(playlist.playcuts.first?.upcomingShow?.status == .soldOut)
        #expect(playlist.playcuts.first?.upcomingShow?.venue.name == "Cat's Cradle")
    }

    @Test("Playcut has no upcomingShow when the entry omits it")
    func noUpcomingShowWhenAbsent() {
        let entry = FlowsheetEntry(
            id: 124,
            show_id: 456,
            album_id: nil,
            artist_name: "Juana Molina",
            album_title: "DOGA",
            track_title: "la paradoja",
            record_label: "Sonamos",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 2,
            add_time: "2026-04-17T22:53:48.500Z"
        )

        let playlist = FlowsheetConverter.convert([entry])
        #expect(playlist.playcuts.first?.upcomingShow == nil)
    }

    // MARK: - Embedded critic_reviews (#695)

    @Test("Carries feed-inline critic_reviews through to the playcut")
    func carriesCriticReviews() {
        let review = CriticReview(
            source: "The Quietus",
            url: URL(string: "https://thequietus.com/articles/juana-molina-doga")!,
            snippet: "A restless, shape-shifting record that never settles.",
            author: "Jane Critic",
            publishedDate: "2024-03-15",
            rating: "8.0"
        )
        let entry = FlowsheetEntry(
            id: 125,
            show_id: 456,
            album_id: 660123,
            artist_name: "Juana Molina",
            album_title: "DOGA",
            track_title: "la paradoja",
            record_label: "Sonamos",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 3,
            add_time: "2026-04-17T22:53:48.500Z",
            critic_reviews: [TolerantCriticReviewItem(review: review)]
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.playcuts.count == 1)
        #expect(playlist.playcuts.first?.criticReviews == [review])
    }

    @Test("Playcut has no criticReviews when the entry omits it")
    func noCriticReviewsWhenAbsent() {
        let entry = FlowsheetEntry(
            id: 126,
            show_id: 456,
            album_id: nil,
            artist_name: "Juana Molina",
            album_title: "DOGA",
            track_title: "la paradoja",
            record_label: "Sonamos",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 4,
            add_time: "2026-04-17T22:53:48.500Z"
        )

        let playlist = FlowsheetConverter.convert([entry])
        #expect(playlist.playcuts.first?.criticReviews == nil)
    }

    @Test("A malformed critic_reviews item does not drop the surviving reviews")
    func oneMalformedCriticReviewItemIsDropped() {
        let survivor = CriticReview(
            source: "The Quietus",
            url: URL(string: "https://thequietus.com/articles/second")!,
            snippet: "Required-fields-only card."
        )
        let entry = FlowsheetEntry(
            id: 127,
            show_id: 456,
            album_id: nil,
            artist_name: "Juana Molina",
            album_title: "DOGA",
            track_title: "la paradoja",
            record_label: "Sonamos",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 5,
            add_time: "2026-04-17T22:53:48.500Z",
            // The wrapper's own decode already dropped the malformed item, so
            // this simulates the post-decode shape: one nil (dropped), one
            // survivor. The actual JSON-decode-time drop is covered by
            // FlowsheetResponseOnAirTests's per-item robustness suite.
            critic_reviews: [TolerantCriticReviewItem(review: nil), TolerantCriticReviewItem(review: survivor)]
        )

        let playlist = FlowsheetConverter.convert([entry])
        #expect(playlist.playcuts.first?.criticReviews == [survivor])
    }

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
        // Composite key: (show_id << 32) | play_order, not the bare id (#839).
        #expect(playcut.chronOrderID == (UInt64(456) << 32) | 1)
    }

    @Test("Converts talkset entry correctly when message is 'Talkset'")
    func convertsTalksetEntry() {
        let entry = FlowsheetEntry(
            id: 124,
            show_id: 456,
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
        // Every entry type takes the same packed key, not just playcuts (#839).
        #expect(talkset.chronOrderID == (UInt64(456) << 32) | 2)
    }

    @Test("Converts breakpoint entry correctly when message contains 'Breakpoint'")
    func convertsBreakpointEntry() {
        let entry = FlowsheetEntry(
            id: 125,
            show_id: 456,
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
        #expect(breakpoint.chronOrderID == (UInt64(456) << 32) | 3)
    }

    @Test("Converts show start marker correctly")
    func convertsShowStartMarker() {
        let entry = FlowsheetEntry(
            id: 126,
            show_id: 456,
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
        #expect(marker.chronOrderID == (UInt64(456) << 32) | 4)
    }

    @Test("Converts show end marker correctly")
    func convertsShowEndMarker() {
        let entry = FlowsheetEntry(
            id: 127,
            show_id: 456,
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
        #expect(marker.chronOrderID == (UInt64(456) << 32) | 5)
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

        // Two track rows: the minimal Miyako Koda row and the fully-populated
        // Jessica Pratt row added for the codegen parity test (#600).
        #expect(playlist.playcuts.count == 2)
        #expect(playlist.talksets.count == 1)
        #expect(playlist.breakpoints.count == 1)
        #expect(playlist.showMarkers.count == 2)

        let playcut = try #require(playlist.playcuts.first { $0.artistName == "Miyako Koda" })
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

    @Test("Breakpoint hour falls back to add_time when radio_hour is a pre-1970 instant")
    func breakpointFallsBackToAddTimeWhenRadioHourPre1970() throws {
        // A pre-1970 `radio_hour` parses to a negative interval; converting it to
        // an unsigned millisecond count must not trap. Treat it as invalid and
        // fall back to `add_time` rather than crashing the whole conversion.
        let entry = FlowsheetEntry(
            id: 304, show_id: nil, album_id: nil,
            artist_name: nil, album_title: nil, track_title: nil,
            record_label: nil, rotation_id: nil, rotation_play_freq: nil,
            request_flag: nil, message: nil, play_order: 1,
            add_time: "2024-01-15T15:58:42Z",
            entry_type: "breakpoint",
            radio_hour: "1969-12-31T23:00:00Z"
        )

        let playlist = FlowsheetConverter.convert([entry])
        let breakpoint = try #require(playlist.breakpoints.first)

        let expectedAddTime = UInt64(try Date("2024-01-15T15:58:42Z", strategy: .iso8601).timeIntervalSince1970 * 1000)
        #expect(breakpoint.hour == expectedAddTime)
        #expect(breakpoint.timeCreated == expectedAddTime)
    }

    // MARK: - dj_join / dj_leave markers are dropped (#693)

    @Test(
        "dj_join/dj_leave rows produce no playcut, talkset, breakpoint, or showMarker",
        arguments: ["dj_join", "dj_leave"]
    )
    func djJoinAndDjLeaveProduceNoTimelineContent(entryType: String) {
        // Real wire shape captured from prod (2026-07-28): only
        // id/show_id/play_order/add_time/entry_type/dj_name.
        let marker = FlowsheetEntry(
            id: 5298092, show_id: 1950704, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 39, add_time: "2026-07-28T20:31:58.258Z",
            entry_type: entryType, dj_name: "DJ will"
        )
        let track = FlowsheetEntry(
            id: 5298093, show_id: 1950704, album_id: nil,
            artist_name: "Jessica Pratt", album_title: "On Your Own Love Again",
            track_title: "Back, Baby", record_label: "Drag City",
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 40, add_time: "2026-07-28T20:32:58.258Z",
            entry_type: "track"
        )

        let playlist = FlowsheetConverter.convert([marker, track])

        #expect(playlist.playcuts.count == 1, "only the real track row should become a playcut")
        #expect(playlist.playcuts.first?.artistName == "Jessica Pratt")
        #expect(playlist.talksets.isEmpty)
        #expect(playlist.breakpoints.isEmpty)
        #expect(playlist.showMarkers.isEmpty)
        #expect(playlist.entries.allSatisfy { $0.id != UInt64(marker.id) })
    }

    @Test("Decoding the real dj_join wire shape and converting it alone yields an empty playlist")
    func decodedDjJoinFromWireProducesEmptyPlaylist() throws {
        let json = """
        {"id": 5298092, "show_id": 1950704, "play_order": 39, "add_time": "2026-07-28T20:31:58.258Z", "entry_type": "dj_join", "dj_name": "DJ will"}
        """
        let entry = try JSONDecoder().decode(FlowsheetEntry.self, from: Data(json.utf8))

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.isContentEmpty)
    }

    @Test("Unrecognized future entry_type produces no timeline content")
    func unrecognizedFutureEntryTypeProducesNoTimelineContent() {
        let entry = FlowsheetEntry(
            id: 9, show_id: nil, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 9, add_time: "2026-07-28T20:31:58.258Z",
            entry_type: "some_future_type"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.isContentEmpty)
    }

    @Test("Regression: entry_type == nil still routes through the message-based fallback")
    func nilEntryTypeStillUsesMessageFallback() {
        // Guards against a broad "drop when entry_type doesn't match a known
        // case" refactor accidentally swallowing the legacy nil-entry_type path
        // that old servers/fixtures rely on.
        let entry = FlowsheetEntry(
            id: 10, show_id: nil, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: "Start of Show: DJ Cool joined the set at 10/14/2025 2:00 PM",
            play_order: 10, add_time: "2026-07-28T20:31:58.258Z"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.showMarkers.count == 1)
        #expect(playlist.showMarkers.first?.djName == "DJ Cool")
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

    @Test("#265 regression, expanded: a previous show with MORE logged entries than the current show still surfaces the current show's entries newest-first, in exact order")
    func previousShowWithMoreEntriesStillRanksBehindCurrentShow() {
        // The previous show (show_id 1947063) ran a full set and logged five
        // entries; the current show (show_id 1947064) has only logged two so
        // far. Ranking on play_order alone would float the previous show's
        // high-play_order tail above the current show's freshly-reset head —
        // the #265 regression. The show_id component of the packed key must
        // dominate regardless of how many more entries the previous show has.
        let previousShowEntries = (1...5).map { n in
            FlowsheetEntry(
                id: 5210349 + n, show_id: 1947063, album_id: nil,
                artist_name: "Luomo", album_title: "Vocalcity",
                track_title: "Track \(n)", record_label: "Force Tracks",
                rotation_id: nil, rotation_play_freq: nil,
                request_flag: false, message: nil,
                play_order: 30 + n, add_time: "2026-05-14T2\(n):00:00.000Z",
                entry_type: "track"
            )
        }
        let currentShowEntries = (1...2).map { n in
            FlowsheetEntry(
                id: 5210394 + n, show_id: 1947064, album_id: nil,
                artist_name: "Tortoise", album_title: "Standards",
                track_title: "Current Track \(n)", record_label: "Thrill Jockey Records",
                rotation_id: nil, rotation_play_freq: nil,
                request_flag: false, message: nil,
                play_order: n, add_time: "2026-05-15T01:4\(n):00.000Z",
                entry_type: "track"
            )
        }

        let playlist = FlowsheetConverter.convert(previousShowEntries + currentShowEntries)
        let sortedIDs = playlist.entries.map(\.id)

        // Current show's two entries (newest play_order first), then the
        // entire previous show's five entries (newest play_order first) —
        // even though the previous show logged more rows overall.
        #expect(sortedIDs == [5210396, 5210395, 5210354, 5210353, 5210352, 5210351, 5210350])
    }

    // MARK: - Composite (show_id, play_order) ordering (#839)

    @Test("A dj-site reorder that lowers play_order sorts the row into its new position, not its id position")
    func sortsByPlayOrderNotID() {
        // The headline #839 scenario: a DJ logs a track, then hits TALKSET —
        // the talkset's id is higher (logged later), so under the old
        // id-only key it renders above the track it actually preceded. The
        // DJ drags the talkset below the track on dj-site (`changeOrder`),
        // which lowers its play_order without changing its id.
        let track = FlowsheetEntry(
            id: 500, show_id: 42, album_id: nil,
            artist_name: "Jessica Pratt", album_title: "On Your Own Love Again",
            track_title: "Back, Baby", record_label: "Drag City",
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 5, add_time: "2026-07-31T18:00:00Z",
            entry_type: "track"
        )
        let reorderedTalkset = FlowsheetEntry(
            id: 501, show_id: 42, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 4, add_time: "2026-07-31T18:00:05Z",
            entry_type: "talkset"
        )

        let playlist = FlowsheetConverter.convert([track, reorderedTalkset])
        let sorted = playlist.entries

        #expect(sorted.count == 2)
        #expect(sorted[0].id == 500, "the track must rank first even though the talkset has a higher id")
        #expect(sorted[1].id == 501)
    }

    @Test("Packs (show_id, play_order) via a left shift, not a decimal multiplier")
    func packsShowIDAndPlayOrderViaShift() {
        let entry = FlowsheetEntry(
            id: 999, show_id: 1_950_704, album_id: nil, artist_name: nil,
            album_title: nil, track_title: nil, record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: nil,
            message: nil, play_order: 12, add_time: "2026-07-31T18:00:00Z",
            entry_type: "talkset"
        )

        let playlist = FlowsheetConverter.convert([entry])
        let expected = (UInt64(1_950_704) << 32) | UInt64(12)

        #expect(playlist.talksets.first?.chronOrderID == expected)
        // A decimal K=1000 multiplier has only ~20x headroom over the
        // observed max play_order (50 in a 3-hour show) and would silently
        // collide once breached; the shift has ~2000x headroom at today's
        // show_id magnitude and needs no boundary test.
        #expect(expected != UInt64(1000 * 1_950_704 + 12))
    }

    // MARK: - Unpackable rows fall back to the legacy id key (#839)

    @Test("A nil show_id never outranks a real packed key")
    func nilShowIDNeverOutranksARealPackedKey() {
        // Decoder tolerance for a malformed/legacy row: Backend-Service
        // itself 500s on a nil show_id in `changeOrder`, and every row in a
        // live 200-row sample carried one post-#693, so this is not a
        // real-traffic path. There is no *correct* key for a row that names
        // no show, so the fallback is chosen for how it fails: a bare
        // `UInt64(id)` (~5e6) ranks below every real packed key (~8e15), so
        // the row lands at the bottom of the feed. The alternative — shifting
        // `id` into the high bits the way real keys are shifted — ranks it
        // ABOVE every real row indefinitely (`id` runs ~2.7x `show_id`), which
        // hands it the on-air banner, the now-playing surfaces, and the
        // Spotlight watermark. Bottom is recoverable; top is not.
        let nilShowEntry = FlowsheetEntry(
            id: 5_304_200, show_id: nil, album_id: nil,
            artist_name: "Hermanos Gutiérrez", album_title: "El Bueno y el Malo",
            track_title: "Los Gemelos", record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 4, add_time: "2026-07-31T18:00:00Z",
            entry_type: "track"
        )
        let realShowEntry = FlowsheetEntry(
            id: 5_304_199, show_id: 1_950_704, album_id: nil,
            artist_name: "Csillagrablók", album_title: "Idővonat",
            track_title: "Nyugalom", record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 5, add_time: "2026-07-31T17:59:00.000Z",
            entry_type: "track"
        )

        let playlist = FlowsheetConverter.convert([realShowEntry, nilShowEntry])

        #expect(playlist.entries.first?.id == 5_304_199, "a real packed key must outrank the unpackable row")
        #expect(playlist.playcuts.first { $0.id == 5_304_200 }?.chronOrderID == UInt64(5_304_200))
    }

    @Test("A feed that carries no show_id at all degrades to the pre-#839 id ordering")
    func everyRowMissingShowIDDegradesToLegacyIDOrdering() {
        // The fallback's real design point. If Backend ever stops emitting
        // `show_id` — a field regression, not a malformed single row — every
        // row takes the fallback, and because the fallback IS the old key the
        // whole feed silently reverts to #839's predecessor ordering instead
        // of scrambling. Any fallback that shifts `id` would order these
        // identically too; what distinguishes this one is that it stays in
        // the same numeric band as the legacy watermark and never outranks a
        // real row when the field comes back mid-window.
        let entries = (0..<4).map { n in
            FlowsheetEntry(
                id: 5_304_300 + n, show_id: nil, album_id: nil,
                artist_name: "Juana Molina", album_title: "DOGA",
                track_title: "la paradoja \(n)", record_label: "Sonamos",
                rotation_id: nil, rotation_play_freq: nil, request_flag: false,
                message: nil, play_order: n + 1, add_time: "2026-07-31T18:0\(n):00Z",
                entry_type: "track"
            )
        }

        let playlist = FlowsheetConverter.convert(entries)

        #expect(playlist.entries.map(\.id) == [5_304_303, 5_304_302, 5_304_301, 5_304_300])
    }

    @Test("The nil-show_id fallback is identical on the REST and single-entry SSE paths")
    func nilShowIDFallbackMatchesAcrossRESTAndSSE() throws {
        let entry = FlowsheetEntry(
            id: 5_304_201, show_id: nil, album_id: nil,
            artist_name: "Nilüfer Yanya", album_title: nil,
            track_title: "Midnight Sun", record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 7, add_time: "2026-07-31T18:00:00Z",
            entry_type: "track"
        )

        let restPlaycut = try #require(FlowsheetConverter.convert([entry]).playcuts.first)
        let ssePlaycut = try Self.decodeAsSingleEntrySSEInsert(entry)

        #expect(restPlaycut.chronOrderID == ssePlaycut.chronOrderID)
        #expect(restPlaycut.chronOrderID == UInt64(5_304_201))
    }

    @Test(
        "An out-of-range show_id or play_order falls back to the id key instead of trapping or corrupting the packing",
        arguments: [
            (-1, 4, "a negative show_id traps `UInt64.init`"),
            (1_950_704, -1, "a negative play_order traps `UInt64.init`"),
            (Int(UInt32.max) + 1, 4, "a show_id past 32 bits loses its high bits to the shift"),
            (1_950_704, Int(UInt32.max) + 1, "a play_order past 32 bits carries into the show bits"),
        ]
    )
    func outOfRangeComponentsFallBackToTheIDKey(showID: Int, playOrder: Int, why: String) {
        // `UInt64(_:)` traps on a negative `Int`, so a single malformed row
        // would crash every poll and every SSE frame — the same hazard
        // `milliseconds(since1970:)` rejects rather than crashing on. The
        // 32-bit breaches are the silent half: they'd produce a plausible
        // key that sorts wrong forever with nothing to notice.
        let entry = FlowsheetEntry(
            id: 5_304_400, show_id: showID, album_id: nil,
            artist_name: "Cat Power", album_title: "Moon Pix",
            track_title: "Cross Bones Style", record_label: "Matador",
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: playOrder, add_time: "2026-07-31T18:00:00Z",
            entry_type: "track"
        )

        let playlist = FlowsheetConverter.convert([entry])

        #expect(playlist.playcuts.first?.chronOrderID == UInt64(5_304_400), Comment(rawValue: why))
    }

    // MARK: - REST/SSE key parity (#839)

    @Test("REST and single-entry SSE paths derive identical chronOrderID for the same FlowsheetEntry")
    func restAndSSEProduceIdenticalChronOrderID() throws {
        let entry = FlowsheetEntry(
            id: 5_304_111, show_id: 1_950_704, album_id: nil,
            artist_name: "Chuquimamani-Condori", album_title: "Edits",
            track_title: "Call Your Name", record_label: nil,
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 12, add_time: "2026-07-31T18:00:00Z",
            entry_type: "track"
        )
        // A second row in the same REST batch proves the per-row key doesn't
        // depend on batch context/array position.
        let otherEntryInBatch = FlowsheetEntry(
            id: 5_304_100, show_id: 1_950_704, album_id: nil,
            artist_name: "Stereolab", album_title: "Aluminum Tunes",
            track_title: "Pack Yr Romantic Mind", record_label: "Duophonic",
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 11, add_time: "2026-07-31T17:59:00.000Z",
            entry_type: "track"
        )

        let restPlaycut = try #require(
            FlowsheetConverter.convert([otherEntryInBatch, entry]).playcuts.first { $0.id == 5_304_111 }
        )
        let ssePlaycut = try Self.decodeAsSingleEntrySSEInsert(entry)

        #expect(restPlaycut.chronOrderID == ssePlaycut.chronOrderID)
    }

    // MARK: - Duplicate composite keys (#839)

    @Test("Duplicate (show_id, play_order) pairs sort deterministically by id, regardless of input order")
    func duplicateCompositeKeysBreakTieByID() {
        // A dj-site reorder shifts a contiguous play_order range in one
        // transaction, but only the enriched subset of that range broadcasts
        // over live-fs-topic — so between polls the app can hold a
        // pre-reorder AND a post-reorder row that both claim the same
        // (show_id, play_order). Swift's `sorted` is not stable, so an
        // unbroken tie would present a different relative order on every
        // render; the comparator must resolve it via id.
        let staleCopy = FlowsheetEntry(
            id: 5_304_100, show_id: 1_950_704, album_id: nil,
            artist_name: "Stereolab", album_title: "Aluminum Tunes",
            track_title: "Pack Yr Romantic Mind", record_label: "Duophonic",
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 12, add_time: "2026-07-31T18:00:00Z",
            entry_type: "track"
        )
        let freshCopy = FlowsheetEntry(
            id: 5_304_111, show_id: 1_950_704, album_id: nil,
            artist_name: "Cat Power", album_title: "Moon Pix",
            track_title: "Moonshiner", record_label: "Matador Records",
            rotation_id: nil, rotation_play_freq: nil, request_flag: false,
            message: nil, play_order: 12, add_time: "2026-07-31T18:00:05Z",
            entry_type: "track"
        )

        let forward = FlowsheetConverter.convert([staleCopy, freshCopy]).entries.map(\.id)
        let reversed = FlowsheetConverter.convert([freshCopy, staleCopy]).entries.map(\.id)

        #expect(forward == [5_304_111, 5_304_100])
        #expect(reversed == [5_304_111, 5_304_100])
        #expect(forward == reversed)
    }

    // MARK: - Test helpers

    /// Decodes `entry` as a single-entry `live-fs-topic` insert frame — the
    /// same shape `LiveFsEvent(frameData:)` parses in production — and
    /// returns the resulting `Playcut`. Used to prove the SSE path derives
    /// the identical `chronOrderID` the REST path does for the same row.
    private static func decodeAsSingleEntrySSEInsert(_ entry: FlowsheetEntry) throws -> Playcut {
        let payloadData = try JSONEncoder().encode(entry)
        let payloadObject = try JSONSerialization.jsonObject(with: payloadData)
        let frameObject: [String: Any] = [
            "type": "insert",
            "timestamp": "2026-07-31T18:00:00Z",
            "payload": payloadObject
        ]
        let frameData = try JSONSerialization.data(withJSONObject: frameObject)

        guard case let .insert(playcut) = try #require(LiveFsEvent(frameData: frameData)) else {
            Issue.record("expected .insert")
            throw TestHelperError.unexpectedEventType
        }
        return playcut
    }

    private enum TestHelperError: Error {
        case unexpectedEventType
    }
}

// MARK: - artist_id projection (BS#1625 / #492)

@Suite("FlowsheetConverter artist_id Tests")
struct FlowsheetConverterArtistIdTests {

    @Test("FlowsheetEntry decodes artist_id from the wire and defaults to nil when absent")
    func decodesArtistIdFromWire() throws {
        let json = """
        {
            "id": 5194728, "show_id": 1946226, "play_order": 30,
            "add_time": "2026-04-17T22:53:48.500Z", "entry_type": "track",
            "artist_name": "Jessica Pratt", "track_title": "Back, Baby", "artist_id": 812
        }
        """
        let entry = try JSONDecoder().decode(FlowsheetEntry.self, from: Data(json.utf8))
        #expect(entry.artist_id == 812)

        let jsonAbsent = """
        {
            "id": 5194728, "show_id": 1946226, "play_order": 30,
            "add_time": "2026-04-17T22:53:48.500Z", "entry_type": "track",
            "artist_name": "Jessica Pratt", "track_title": "Back, Baby"
        }
        """
        let legacy = try JSONDecoder().decode(FlowsheetEntry.self, from: Data(jsonAbsent.utf8))
        #expect(legacy.artist_id == nil)
    }

    @Test("Carries artist_id through to Playcut.artistId")
    func carriesArtistId() {
        let entry = FlowsheetEntry(
            id: 125,
            show_id: 456,
            album_id: 789,
            artist_name: "Jessica Pratt",
            album_title: "On Your Own Love Again",
            track_title: "Back, Baby",
            record_label: "Drag City",
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 3,
            add_time: "2026-04-17T22:53:48.500Z",
            artist_id: 812
        )

        let playlist = FlowsheetConverter.convert([entry])
        #expect(playlist.playcuts.first?.artistId == 812)
    }

    @Test("Playcut.artistId is nil for a free-text entry (no artist_id on the wire)")
    func freeTextEntryHasNilArtistId() {
        let entry = FlowsheetEntry(
            id: 126,
            show_id: 456,
            album_id: nil,
            artist_name: "NIL\u{00DC}FER YANYA",
            album_title: nil,
            track_title: "Midnight Sun",
            record_label: nil,
            rotation_id: nil,
            rotation_play_freq: nil,
            request_flag: false,
            message: nil,
            play_order: 4,
            add_time: "2026-04-17T22:53:48.500Z"
        )

        let playlist = FlowsheetConverter.convert([entry])
        #expect(playlist.playcuts.first?.artistId == nil)
    }
}
