//
//  ConcertMonthSection.swift
//  Concerts
//
//  Breaks the On Tour list's flat, `starts_on`-ascending concert window into
//  month-titled sections. Pure by design — a value-in/value-out transform over
//  `[Concert]`, mirroring `ForYouShelf` — so the view just renders whatever
//  sections come back and the grouping stays testable without a view or a clock.
//
//  Every month boundary is computed in the station zone (`America/New_York`),
//  the same zone `Concert.startsOn` is parsed in, so a show on the 1st of a month
//  never leaks into the prior month on a device west of Eastern.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A run of concerts that fall in the same calendar month, used to break the
/// On Tour list into month-titled sections.
///
/// Built by ``sections(for:)``; the view renders one section header per element
/// followed by its ``concerts``.
public struct ConcertMonthSection: Identifiable, Equatable, Sendable {

    /// Stable identity: the month as `yyyy-MM` in the station zone (e.g.
    /// `"2026-08"`). Sortable as a string *and* stable across reloads, so SwiftUI
    /// keeps section identity when the window refreshes.
    public let id: String

    /// The section header, e.g. `"August 2026"`. Carries the year so a window that
    /// spans a December→January boundary reads unambiguously.
    public let title: String

    /// The concerts in this month, preserving the input window's order (which is
    /// `starts_on` ascending from the server).
    public let concerts: [Concert]

    public init(id: String, title: String, concerts: [Concert]) {
        self.id = id
        self.title = title
        self.concerts = concerts
    }
}

public extension ConcertMonthSection {

    /// Groups a concert window into chronological month sections.
    ///
    /// The month key and title are computed in the station zone, so the grouping
    /// is independent of the device's zone or locale. Sections come back sorted
    /// ascending by month; within each section the concerts keep the order they
    /// arrived in. The grouping does not assume the input is sorted — an
    /// out-of-order window still yields exactly one section per month — but the
    /// server sends `starts_on` ascending, so in practice the whole result is
    /// already chronological.
    ///
    /// - Parameter concerts: The window to group (typically `OnTourModel.filtered`).
    /// - Returns: One ``ConcertMonthSection`` per month present, ascending.
    static func sections(for concerts: [Concert]) -> [ConcertMonthSection] {
        var order: [String] = []
        var buckets: [String: [Concert]] = [:]
        var titles: [String: String] = [:]

        for concert in concerts {
            let components = Self.stationCalendar.dateComponents([.year, .month], from: concert.startsOn)
            // `.year`/`.month` are always present for a valid `Date`; the guard is
            // a total-function safeguard, not a reachable branch.
            guard let year = components.year, let month = components.month else { continue }
            let key = String(format: "%04d-%02d", year, month)
            if buckets[key] == nil {
                order.append(key)
                titles[key] = Self.titleFormatter.string(from: concert.startsOn)
            }
            buckets[key, default: []].append(concert)
        }

        return order
            .sorted()  // `yyyy-MM` sorts lexicographically == chronologically
            .map { ConcertMonthSection(id: $0, title: titles[$0] ?? $0, concerts: buckets[$0] ?? []) }
    }

    /// Station-zone Gregorian calendar for deriving the year/month key.
    private static let stationCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        return calendar
    }()

    /// Station-zone, fixed-locale formatter for the section title (`"August 2026"`),
    /// matching the deterministic date labels elsewhere in the package.
    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .wxycStation
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
