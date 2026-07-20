//
//  TimeZone+Station.swift
//  Concerts
//
//  The station's broadcast time zone, and the station-zone date machinery built
//  on it — a shared `Calendar` and a `DateFormatter` factory — used to pin
//  `starts_on` date parsing, month grouping, and the Box Office ticket's
//  date/time labels to a fixed zone regardless of the device's locale.
//
//  Declared locally in this package (mirroring the same internal extension in
//  `Shared/Playlist`) so `Concerts` stays self-contained and does not depend on
//  `Playlist` — the dependency runs the other way (Playlist → Concerts). The two
//  module-scoped declarations do not collide.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension TimeZone {
    /// The station's broadcast time zone. WXYC broadcasts from Chapel Hill, NC
    /// (US Eastern). The `?? .gmt` fallback is unreachable for this fixed,
    /// always-known identifier but keeps the declaration force-unwrap-free.
    static let wxycStation = TimeZone(identifier: "America/New_York") ?? .gmt
}

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

extension DateFormatter {
    /// Builds a station-zone, fixed-`en_US_POSIX`-locale `DateFormatter` for a
    /// single format string, so a label renders identically regardless of the
    /// device's zone or locale.
    static func station(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .wxycStation
        formatter.dateFormat = format
        return formatter
    }
}
