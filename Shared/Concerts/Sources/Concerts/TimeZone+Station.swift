//
//  TimeZone+Station.swift
//  Concerts
//
//  The station-zone date machinery built on `Core`'s `TimeZone.wxycStation` —
//  a shared `Calendar` — used to pin `starts_on` date parsing, month grouping,
//  and the Box Office ticket's date/time labels to a fixed zone regardless of
//  the device's locale.
//
//  `TimeZone.wxycStation` and the `en_US_POSIX` station `DateFormatter`
//  factory used to be declared here too (mirroring an identical copy in
//  `Shared/Playlist`), each package avoiding a dependency for one constant even
//  though both already depend on `Core`. Hoisted to `Core` instead — see
//  issue #771.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

extension Calendar {
    /// A Gregorian calendar pinned to the station zone, for deriving calendar
    /// components (day/month/year) from a `starts_on` instant independent of the
    /// device's zone or calendar.
    static let wxycStation: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        return calendar
    }()
}

extension Date {
    /// A station-zone wall-clock label (`"7 PM"` / `"8:30 PM"`), dropping the
    /// minutes when the time falls on the hour. The one venue-local time label
    /// shared by the Box Office ticket's door/show times and the Add-to-Calendar
    /// doors note, so both read identically.
    func stationWallClock() -> String {
        let minute = Calendar.wxycStation.component(.minute, from: self)
        let formatter = minute == 0 ? Self.stationHourOnly : Self.stationHourMinute
        return formatter.string(from: self)
    }

    private static let stationHourOnly = DateFormatter.station("h a")
    private static let stationHourMinute = DateFormatter.station("h:mm a")
}
