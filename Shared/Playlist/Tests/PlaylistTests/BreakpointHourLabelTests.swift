//
//  BreakpointHourLabelTests.swift
//  Playlist
//
//  Created by Jake Bromberg on 06/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

// The breakpoint hour chip is anchored to the station's time zone (Eastern,
// where WXYC broadcasts). A listener already in Eastern sees the hour once;
// a listener elsewhere sees their local hour alongside the station's.
@Suite("Breakpoint hour-label formatting")
struct BreakpointHourLabelTests {
    private let eastern = TimeZone(identifier: "America/New_York")!
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!
    private let toronto = TimeZone(identifier: "America/Toronto")!

    private func milliseconds(_ iso: String) throws -> UInt64 {
        UInt64(try Date(iso, strategy: .iso8601).timeIntervalSince1970 * 1000)
    }

    @Test("Eastern listener sees the station hour once, e.g. \"3PM ET\"")
    func easternListenerSeesSingleLabel() throws {
        // 2026-06-18T19:00:00Z == 3 PM EDT
        let breakpoint = Breakpoint.stub(hour: try milliseconds("2026-06-18T19:00:00Z"))
        #expect(breakpoint.hourLabel(localTimeZone: eastern) == "3PM ET")
    }

    @Test("Non-Eastern listener sees local hour then station hour, e.g. \"12PM PT / 3PM ET\"")
    func pacificListenerSeesBothLabels() throws {
        // 2026-06-18T19:00:00Z == 12 PM PDT == 3 PM EDT
        let breakpoint = Breakpoint.stub(hour: try milliseconds("2026-06-18T19:00:00Z"))
        #expect(breakpoint.hourLabel(localTimeZone: pacific) == "12PM PT / 3PM ET")
    }

    @Test("A non-Eastern zone sharing Eastern's offset still collapses to one label")
    func sameOffsetZoneCollapsesToSingleLabel() throws {
        // America/Toronto observes US Eastern — same UTC offset as New York, but a
        // different identifier — so the listener reads station time directly. The
        // collapse keys on the offset, not the identifier. 16:00:00Z == 11 AM EST.
        let breakpoint = Breakpoint.stub(hour: try milliseconds("2024-01-15T16:00:00Z"))
        #expect(breakpoint.hourLabel(localTimeZone: toronto) == "11AM ET")
    }

    @Test("Noon and midnight render as 12PM and 12AM, not 0")
    func noonAndMidnightFormatting() throws {
        // 2026-06-18T16:00:00Z == 12 PM EDT; 2026-06-18T04:00:00Z == 12 AM EDT.
        let noon = Breakpoint.stub(hour: try milliseconds("2026-06-18T16:00:00Z"))
        let midnight = Breakpoint.stub(hour: try milliseconds("2026-06-18T04:00:00Z"))
        #expect(noon.hourLabel(localTimeZone: eastern) == "12PM ET")
        #expect(midnight.hourLabel(localTimeZone: eastern) == "12AM ET")
    }

    @Test("Converted breakpoint renders the radio_hour hour, not the add_time hour (ios#404)")
    func convertedBreakpointRendersRadioHour() throws {
        // In Eastern: add_time 15:58:42Z would floor to "10AM"; radio_hour
        // 16:00:00Z is the real top-of-hour, "11AM".
        let entry = FlowsheetEntry(
            id: 400, show_id: nil, album_id: nil,
            artist_name: nil, album_title: nil, track_title: nil,
            record_label: nil, rotation_id: nil, rotation_play_freq: nil,
            request_flag: nil, message: nil, play_order: 1,
            add_time: "2024-01-15T15:58:42Z",
            entry_type: "breakpoint",
            radio_hour: "2024-01-15T16:00:00Z"
        )
        let breakpoint = try #require(FlowsheetConverter.convert([entry]).breakpoints.first)
        #expect(breakpoint.hourLabel(localTimeZone: eastern) == "11AM ET")
    }
}
