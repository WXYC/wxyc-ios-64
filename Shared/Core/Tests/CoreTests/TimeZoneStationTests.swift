//
//  TimeZoneStationTests.swift
//  Core
//
//  Guards the station time zone/date-formatter contract that `Concerts`,
//  `Playlist`, and several app-target call sites all pin `starts_on`/broadcast
//  labels to: US Eastern, and an `en_US_POSIX`-locale `DateFormatter` so a
//  label renders identically regardless of the device's zone or locale.
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
