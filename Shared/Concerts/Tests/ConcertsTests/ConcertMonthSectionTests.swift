//
//  ConcertMonthSectionTests.swift
//  Concerts
//
//  Coverage for the month-grouping that breaks the On Tour list into
//  month-titled sections: single vs. multi-month grouping, chronological
//  ordering, within-month order preservation, the station-zone month boundary,
//  and the stable section id / title format. The grouping is pure — a
//  value-in/value-out transform over `[Concert]` — so the tests are plain
//  fixtures with no view, clock, or zone injection.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

@Suite("ConcertMonthSection")
struct ConcertMonthSectionTests {

    // MARK: - Helpers

    /// A `starts_on`-shaped `Date`: midnight of the given calendar day in the
    /// station zone, exactly as `Concert.dateParser` produces from a `yyyy-MM-dd`.
    private func stationDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - Degenerate input

    @Test("An empty window yields no sections")
    func emptyInput() {
        #expect(ConcertMonthSection.sections(for: []).isEmpty)
    }

    // MARK: - Single month

    @Test("Concerts in one month collapse to a single titled section, in order")
    func singleMonth() {
        let a = Concert.stub(id: 1, startsOn: stationDay(2026, 8, 3))
        let b = Concert.stub(id: 2, startsOn: stationDay(2026, 8, 20))
        let sections = ConcertMonthSection.sections(for: [a, b])

        #expect(sections.count == 1)
        #expect(sections[0].title == "August 2026")
        #expect(sections[0].id == "2026-08")
        #expect(sections[0].concerts.map(\.id) == [1, 2])
    }

    // MARK: - Multiple months

    @Test("Concerts spanning months split into chronological sections")
    func multipleMonths() {
        let aug = Concert.stub(id: 1, startsOn: stationDay(2026, 8, 15))
        let sep1 = Concert.stub(id: 2, startsOn: stationDay(2026, 9, 2))
        let sep2 = Concert.stub(id: 3, startsOn: stationDay(2026, 9, 28))
        let oct = Concert.stub(id: 4, startsOn: stationDay(2026, 10, 1))
        let sections = ConcertMonthSection.sections(for: [aug, sep1, sep2, oct])

        #expect(sections.map(\.title) == ["August 2026", "September 2026", "October 2026"])
        #expect(sections.map { $0.concerts.map(\.id) } == [[1], [2, 3], [4]])
    }

    @Test("A December-to-January window carries the year into the title and ordering")
    func yearBoundary() {
        let dec = Concert.stub(id: 1, startsOn: stationDay(2026, 12, 20))
        let jan = Concert.stub(id: 2, startsOn: stationDay(2027, 1, 5))
        let sections = ConcertMonthSection.sections(for: [dec, jan])

        #expect(sections.map(\.title) == ["December 2026", "January 2027"])
        #expect(sections.map(\.id) == ["2026-12", "2027-01"])
    }

    // MARK: - Station-zone boundary

    @Test("The month boundary is computed in the station zone, not the device zone")
    func stationZoneBoundary() {
        // Midnight Sept 1 in the station zone is Aug 31 in any zone west of
        // Eastern. Grouping in the station zone must file it under September.
        let firstOfSeptember = Concert.stub(id: 1, startsOn: stationDay(2026, 9, 1))
        let sections = ConcertMonthSection.sections(for: [firstOfSeptember])

        #expect(sections.count == 1)
        #expect(sections[0].id == "2026-09")
        #expect(sections[0].title == "September 2026")
    }

    // MARK: - Ordering robustness

    @Test("Out-of-order input still yields chronological, non-duplicated sections")
    func defensiveReordering() {
        // The server sends starts_on ascending, but grouping must not depend on it:
        // an interleaved window still produces one section per month, chronological,
        // preserving each concert's encounter order within its month.
        let sepLate = Concert.stub(id: 3, startsOn: stationDay(2026, 9, 20))
        let augEarly = Concert.stub(id: 1, startsOn: stationDay(2026, 8, 5))
        let sepEarly = Concert.stub(id: 2, startsOn: stationDay(2026, 9, 4))
        let augLate = Concert.stub(id: 4, startsOn: stationDay(2026, 8, 25))
        let sections = ConcertMonthSection.sections(for: [sepLate, augEarly, sepEarly, augLate])

        #expect(sections.map(\.id) == ["2026-08", "2026-09"])
        // Within a month, first-seen order is preserved (3 before... no: the
        // September bucket sees id 3 first, then id 2).
        #expect(sections[0].concerts.map(\.id) == [1, 4])
        #expect(sections[1].concerts.map(\.id) == [3, 2])
    }
}
