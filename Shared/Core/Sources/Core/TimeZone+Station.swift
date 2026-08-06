//
//  TimeZone+Station.swift
//  Core
//
//  The station's broadcast time zone, and the `en_US_POSIX` station
//  `DateFormatter` factory built on it, so a label renders identically
//  regardless of the device's zone or locale. Hoisted here (rather than
//  declared per-package) because it was previously duplicated verbatim in
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
