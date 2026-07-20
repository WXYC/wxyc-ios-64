//
//  ConcertCalendarEventTests.swift
//  Concerts
//
//  Tests for the pure calendar-event value type built from a `Concert` (#538).
//  The view layer feeds these fields straight into an `EKEvent`, so all the
//  date math — timed vs. all-day, the default duration, the station-zone doors
//  note — is exercised here without EventKit or a view.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

@Suite("ConcertCalendarEvent")
struct ConcertCalendarEventTests {

    // MARK: - Timed

    @Test("A show with a start instant becomes a timed event")
    func timedEvent() {
        // Stub default: 2026-08-01, doors 7 PM, show 8 PM (station zone).
        let event = ConcertCalendarEvent(.stub())

        #expect(event.isAllDay == false)
        #expect(event.startDate == Concert.stubInstant(hour: 20))
        // No end instant on the wire, so the event blocks the default duration.
        #expect(event.endDate == Concert.stubInstant(hour: 20)?.addingTimeInterval(ConcertCalendarEvent.defaultDuration))
        #expect(event.timeZone == TimeZone(identifier: "America/New_York"))
    }

    @Test("The title is the headline billing")
    func titleIsHeadline() {
        #expect(ConcertCalendarEvent(.stub()).title == "Jessica Pratt")
        // The event's own title wins over the raw headliner when present.
        #expect(ConcertCalendarEvent(.stub(title: "Merge 35: Night Two")).title == "Merge 35: Night Two")
    }

    @Test("The URL is the canonical share link")
    func urlIsShareURL() {
        #expect(ConcertCalendarEvent(.stub(id: 4821)).url == URL(string: "https://wxyc.org/shows/4821"))
    }

    @Test("The location is the geocodable venue line")
    func locationIsVenueLine() {
        #expect(ConcertCalendarEvent(.stub()).location == "Cat's Cradle, 300 E Main St, Carrboro, NC")
    }

    @Test("The location omits a missing street address")
    func locationWithoutAddress() {
        let event = ConcertCalendarEvent(.stub(venue: .stub(address: nil)))
        #expect(event.location == "Cat's Cradle, Carrboro, NC")
    }

    // MARK: - Doors note

    @Test("The doors time rides in the notes when known")
    func doorsNote() {
        #expect(ConcertCalendarEvent(.stub()).notes == "Doors 7 PM")
    }

    @Test("The doors note keeps minutes off the hour")
    func doorsNoteWithMinutes() {
        let event = ConcertCalendarEvent(.stub(doorsAt: Concert.stubInstant(hour: 19, minute: 30)))
        #expect(event.notes == "Doors 7:30 PM")
    }

    // MARK: - Doors-only (no start instant)

    @Test("A doors-only show is all-day with the doors note")
    func doorsOnlyIsAllDay() {
        // No start instant, but doors is known: per the ticket, start keys off
        // `starts_at` only, so this is an all-day event that still notes doors.
        let event = ConcertCalendarEvent(.stub(startsAt: nil, doorsAt: Concert.stubInstant(hour: 19)))

        #expect(event.isAllDay == true)
        #expect(event.startDate == Concert.defaultStartsOn)
        #expect(event.endDate == Concert.defaultStartsOn)
        #expect(event.notes == "Doors 7 PM")
    }

    // MARK: - Date-only (neither instant)

    @Test("A date-only show is an all-day event with no notes")
    func dateOnlyIsAllDay() {
        let event = ConcertCalendarEvent(.stub(startsAt: nil, doorsAt: nil))

        #expect(event.isAllDay == true)
        #expect(event.startDate == Concert.defaultStartsOn)
        #expect(event.endDate == Concert.defaultStartsOn)
        #expect(event.notes == nil)
        // Title, url, and location are still populated for a date-only show.
        #expect(event.title == "Jessica Pratt")
        #expect(event.url == URL(string: "https://wxyc.org/shows/4821"))
        #expect(event.location == "Cat's Cradle, 300 E Main St, Carrboro, NC")
    }
}
