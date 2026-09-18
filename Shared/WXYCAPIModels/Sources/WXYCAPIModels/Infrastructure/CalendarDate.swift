//
//  CalendarDate.swift
//  WXYCAPI
//
//  Canonical Swift type for OpenAPI `format: date` fields -- an ISO 8601
//  calendar date (YYYY-MM-DD) with no time and no timezone. Vendored as
//  ordinary generated-package output via the `postgenerate:swift` npm hook
//  and `typeMappings: date=CalendarDate` in swift6.yaml; never hand-edit a
//  consumer's copy, regenerate from here instead.
//
//  Created by Jake Bromberg on 08/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// An ISO 8601 calendar date (`YYYY-MM-DD`) with no time and no timezone.
///
/// `Foundation.Date` is a point on the UTC timeline; decoding a calendar
/// date into one fabricates a time-of-day and a UTC anchor the value never
/// had, which silently shifts the rendered day by one for any client west
/// of UTC. `CalendarDate` stores only `year`/`month`/`day` and never carries
/// an instant, so that class of defect cannot reappear.
///
/// Comparison is a total order over `(year, month, day)` -- it never
/// consults `Calendar` or `TimeZone`. The only sanctioned way to bridge an
/// instant to a `CalendarDate` is ``init(_:in:)`` / ``today(in:)``: callers
/// choose the zone, and this type owns the conversion.
public struct CalendarDate: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a `CalendarDate` from explicit components, validating that
    /// they name a real calendar day (correct month range, correct days-in-month
    /// including leap years).
    public init(year: Int, month: Int, day: Int) throws {
        guard Self.isValid(year: year, month: month, day: day) else {
            throw CalendarDateError.invalidComponents(year: year, month: month, day: day)
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Trusted construction from components already known to be valid
    /// (validated by the caller). Used internally so validation logic has a
    /// single source of truth without re-checking twice on every path.
    private init(validated year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The sanctioned instant -> day bridge. Converts an absolute instant to
    /// the calendar day it falls on in `timeZone`. Callers choose the zone;
    /// this is the only place that conversion idiom is allowed to happen, so
    /// the off-by-one-day defect this type exists to prevent can't reappear
    /// scattered across call sites.
    ///
    /// This path is non-throwing by design (`today(in:)` must not be a
    /// `try` site), so it does not re-check the `0...9999` year bound that
    /// ``init(year:month:day:)`` enforces. That is safe for every instant
    /// Foundation can hand it in practice: `Date.distantPast` is year 1 and
    /// `Date.distantFuture` is year 4001, and any instant decoded from a
    /// `format: date-time` field is bounded by the same wire format. Only a
    /// deliberately nonsensical `Date` (a `timeIntervalSince1970` some eight
    /// thousand years out) could produce an unencodable year here.
    public init(_ instant: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        // A Gregorian calendar's .year/.month/.day are always present for any
        // valid Date, so these are safe to force-unwrap.
        self.init(validated: components.year!, month: components.month!, day: components.day!)
    }

    /// The current calendar day in `timeZone`.
    public static func today(in timeZone: TimeZone) -> CalendarDate {
        CalendarDate(Date(), in: timeZone)
    }

    // MARK: - Validation (pure arithmetic; no Calendar)

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        // The year bound is the wire format, not an arbitrary limit. RFC 3339's
        // `full-date` is `4DIGIT "-" 2DIGIT "-" 2DIGIT`, `description` renders
        // with `%04d`, and `parse` requires exactly 10 UTF-8 bytes with digits
        // in fixed positions. A year outside 0...9999 therefore encodes to a
        // string this type's own decoder rejects (`10000-01-01` is 11 bytes;
        // `-005-01-01` is 10 but starts with a non-digit), so admitting one
        // would let a caller construct a value that cannot round-trip through
        // the wire form this type exists to represent. Constraining the domain
        // to the wire domain closes that asymmetry by construction.
        guard (0...9999).contains(year) else { return false }
        guard (1...12).contains(month) else { return false }
        guard day >= 1 else { return false }
        return day <= daysInMonth(year: year, month: month)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }

    // MARK: - Fixed-format wire parsing (no DateFormatter/ISO8601DateFormatter/Calendar)

    /// Parses a bare `YYYY-MM-DD` string by fixed-format byte scan.
    ///
    /// `CatalogExportRow` is the NDJSON bulk shape this type decodes inside,
    /// so decode cost is per-row x whole-library -- this deliberately avoids
    /// `DateFormatter`/`ISO8601DateFormatter`/`Calendar`, all of which are
    /// far more expensive than ten digit/dash checks and an arithmetic fold.
    fileprivate static func parse(_ raw: String) throws -> CalendarDate {
        let bytes = Array(raw.utf8)
        guard bytes.count == 10 else {
            throw CalendarDateError.malformed(raw)
        }
        guard bytes[4] == hyphen, bytes[7] == hyphen else {
            throw CalendarDateError.malformed(raw)
        }

        func digit(_ index: Int) throws -> Int {
            let byte = bytes[index]
            guard byte >= zero, byte <= nine else {
                throw CalendarDateError.malformed(raw)
            }
            return Int(byte - zero)
        }

        let year = try digit(0) * 1000 + digit(1) * 100 + digit(2) * 10 + digit(3)
        let month = try digit(5) * 10 + digit(6)
        let day = try digit(8) * 10 + digit(9)

        guard Self.isValid(year: year, month: month, day: day) else {
            throw CalendarDateError.invalidComponents(year: year, month: month, day: day)
        }

        return CalendarDate(validated: year, month: month, day: day)
    }
}

private let hyphen: UInt8 = 0x2D  // "-"
private let zero: UInt8 = 0x30    // "0"
private let nine: UInt8 = 0x39    // "9"

/// A malformed or out-of-range wire value for `format: date`. Per the
/// contract, a malformed date is a server bug -- this type does not attempt
/// to tolerate or repair it, it throws, and per-row decode tolerance
/// (`FailableDecodable` and similar) absorbs the NDJSON blast radius.
public enum CalendarDateError: Error, Sendable, Hashable, CustomStringConvertible {
    case malformed(String)
    case invalidComponents(year: Int, month: Int, day: Int)

    public var description: String {
        switch self {
        case .malformed(let raw):
            return "CalendarDate: malformed value \"\(raw)\", expected YYYY-MM-DD"
        case .invalidComponents(let year, let month, let day):
            return "CalendarDate: \(year)-\(month)-\(day) is not a valid calendar date"
        }
    }
}

extension CalendarDate: Comparable {
    /// Total order over `(year, month, day)`. Deliberately never touches
    /// `Calendar`/`TimeZone` -- two `CalendarDate`s compare purely by their
    /// stored components.
    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CalendarDate: CustomStringConvertible {
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension CalendarDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = try Self.parse(raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
