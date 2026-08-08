//
//  TimeZone+Station.swift
//  Core
//
//  The station's broadcast time zone, the `en_US_POSIX` station
//  `DateFormatter` factory built on it, and the Gregorian `Calendar` pinned to
//  it — so a label renders, and a date decomposes, identically regardless of
//  the device's zone or locale. Hoisted here (rather than declared
//  per-package) because they were previously duplicated verbatim in
//  `Concerts`, `Playlist`, and `ConcertsTesting` — each package avoided taking
//  on a dependency for one constant, even though all three already depend on
//  `Core`. See issue #771.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension TimeZone {
    /// The station's broadcast time zone. WXYC broadcasts from Chapel Hill, NC
    /// (US Eastern). The `?? .gmt` fallback is unreachable for this fixed,
    /// always-known identifier but keeps the declaration force-unwrap-free.
    public static let wxycStation = TimeZone(identifier: "America/New_York") ?? .gmt
}

extension Calendar {
    /// A Gregorian calendar pinned to the station zone, for deriving calendar
    /// components (day/month/year) from an instant independent of the device's
    /// zone or calendar.
    ///
    /// Lives beside ``TimeZone/wxycStation`` rather than in `Concerts` because
    /// `AppServices`, `Playlist`, the app target, and four test suites all
    /// derive one, and a calendar declared inside `Concerts` is invisible to
    /// every one of them.
    public static let wxycStation: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        return calendar
    }()
}

extension DateFormatter {
    /// Builds a station-zone, fixed-`en_US_POSIX`-locale `DateFormatter` for a
    /// single format string, so a label renders identically regardless of the
    /// device's zone or locale.
    public static func station(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .wxycStation
        formatter.dateFormat = format
        return formatter
    }
}
