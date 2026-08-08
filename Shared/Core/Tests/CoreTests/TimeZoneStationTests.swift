//
//  TimeZoneStationTests.swift
//  Core
//
//  Guards the station time zone / calendar / date-formatter contract that
//  `Concerts`, `Playlist`, `AppServices`, and several app-target call sites all
//  pin `starts_on`/broadcast labels to: US Eastern, a Gregorian calendar in
//  that zone, and an `en_US_POSIX`-locale `DateFormatter` so a label renders
//  identically regardless of the device's zone or locale.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Core

@Suite
struct TimeZoneStationTests {
    @Test
    func wxycStationIsUSEastern() {
        #expect(TimeZone.wxycStation.identifier == "America/New_York")
    }

    @Test
    func stationCalendarIsGregorianInTheStationZone() {
        #expect(Calendar.wxycStation.identifier == .gregorian)
        #expect(Calendar.wxycStation.timeZone == .wxycStation)
    }

    /// The reason the calendar is pinned at all: a UTC instant that falls on
    /// the previous day in US Eastern has to decompose as that previous day.
    /// `2026-08-01T02:00:00Z` is 10 PM on July 31 in EDT.
    @Test
    func stationCalendarDecomposesAUTCInstantIntoTheEasternDay() {
        let instant = Date(timeIntervalSince1970: 1_785_549_600)
        let components = Calendar.wxycStation.dateComponents([.year, .month, .day], from: instant)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 31)
    }

    @Test
    func stationFormatterUsesTheStationTimeZone() {
        let formatter = DateFormatter.station("h a")
        #expect(formatter.timeZone == .wxycStation)
    }

    @Test
    func stationFormatterUsesThePOSIXLocale() {
        let formatter = DateFormatter.station("h a")
        #expect(formatter.locale?.identifier == "en_US_POSIX")
    }

    @Test
    func stationFormatterUsesTheGivenFormat() {
        let formatter = DateFormatter.station("yyyy-MM-dd")
        #expect(formatter.dateFormat == "yyyy-MM-dd")
    }
}
