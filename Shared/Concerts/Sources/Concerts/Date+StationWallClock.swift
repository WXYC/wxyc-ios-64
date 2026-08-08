//
//  Date+StationWallClock.swift
//  Concerts
//
//  The station-zone wall-clock label shared by the Box Office ticket's
//  door/show times and the Add-to-Calendar doors note, built on `Core`'s
//  station zone, calendar, and `DateFormatter` factory.
//
//  `TimeZone.wxycStation`, `Calendar.wxycStation`, and the `en_US_POSIX`
//  station `DateFormatter` factory used to be declared here (mirroring
//  identical copies in `Shared/Playlist`, `AppServices`, the app target, and
//  four test suites), each package avoiding a dependency for one constant even
//  though they all already depend on `Core`. Hoisted to `Core` instead — see
//  issue #771.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

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
