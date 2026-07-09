//
//  BoxOfficeTicketPresenter.swift
//  Playlist
//
//  Pure presentation logic for the Box Office ticket. Turns an ``UpcomingShow``
//  into the display strings the SwiftUI view renders — date/time labels, price
//  string, and the per-status pill / CTA / caption copy — so all of that is unit
//  testable without a view. Copy mirrors the approved prototype
//  (docs/ideas/touring-shows-box-office.html).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The visual treatment for the compact feed-row tag, one per ``ShowStatus``.
/// Mirrors the prototype's four `.rtag` variants (`docs/ideas/touring-shows-box-office.html`)
/// so the view maps a semantic style to colors rather than switching on status itself.
public enum FeedTagStyle: Sendable, Equatable {
    /// On sale — the amber accent, drawing the eye toward an attendable show.
    case prominent
    /// Free — the teal accent.
    case free
    /// Sold out — dimmed; still linked, but no longer enticing.
    case muted
    /// Cancelled — a red, "dead" treatment.
    case negative
    /// Unknown — a plain, neutral chip.
    case neutral
}

/// View-model for the Box Office ticket. Every property is a pure function of
/// the wrapped ``UpcomingShow``.
///
/// Date labels use the station time zone and a fixed `en_US_POSIX` locale, the
/// same determinism choice made for `Breakpoint.hourLabel`, so the rendered day
/// never shifts with the device's zone or locale.
public struct BoxOfficeTicketPresenter: Sendable, Equatable {
    public let show: UpcomingShow

    public init(_ show: UpcomingShow) {
        self.show = show
    }

    // MARK: - Date

    /// Full date label, e.g. `"Sat, Aug 1"`.
    public var dateLabel: String {
        Self.dateFormatter.string(from: show.date)
    }

    /// Compact, upper-cased date for the feed-row stub, e.g. `"SAT AUG 1"`.
    public var compactDateLabel: String {
        Self.compactDateFormatter.string(from: show.date).uppercased()
    }

    /// Upper-cased weekday for the ticket stub's date block, e.g. `"SAT"`.
    public var stubWeekday: String {
        Self.weekdayFormatter.string(from: show.date).uppercased()
    }

    /// Day-of-month for the ticket stub's date block, e.g. `"1"`.
    public var stubDayNumber: String {
        Self.dayNumberFormatter.string(from: show.date)
    }

    /// Upper-cased month for the ticket stub's date block, e.g. `"AUG"`.
    public var stubMonth: String {
        Self.monthFormatter.string(from: show.date).uppercased()
    }

    /// A stable, faux "admit one" serial derived from the event id (`"WX-4821"`).
    /// Cosmetic keepsake detail; deterministic so the same show always prints the
    /// same number.
    public var ticketSerial: String {
        "WX-\(show.id)"
    }

    // MARK: - Time

    /// A single time label combining whichever of doors/show times are present:
    /// `"Doors 7 PM · Show 8 PM"`, `"Show 8 PM"`, `"Doors 7 PM"`, or `nil` when
    /// neither is known.
    ///
    /// Times are venue wall-clock values (`HH:mm:ss`) formatted as-is — no zone
    /// conversion, since the printed time is inherently the venue's local time.
    public var timeLabel: String? {
        let doors = show.doorsTime.flatMap(Self.wallClock)
        let showTime = show.showTime.flatMap(Self.wallClock)
        switch (doors, showTime) {
        case let (doors?, show?): return "Doors \(doors) · Show \(show)"
        case let (nil, show?): return "Show \(show)"
        case let (doors?, nil): return "Doors \(doors)"
        case (nil, nil): return nil
        }
    }

    /// The doors time on its own (`"7 PM"`), for a dedicated stat cell. `nil`
    /// when absent.
    public var doorsLabel: String? {
        show.doorsTime.flatMap(Self.wallClock)
    }

    /// The set/show time on its own (`"8 PM"`), for a dedicated stat cell. `nil`
    /// when absent.
    public var showLabel: String? {
        show.showTime.flatMap(Self.wallClock)
    }

    // MARK: - Price

    /// The price string: `"Free"` for a free show, `"$22"` for a single price,
    /// `"$22–$25"` for a range (en dash), or `nil` when unpriced and not free.
    public var priceLabel: String? {
        if show.status == .free { return "Free" }
        let low = show.priceMin ?? show.priceMax
        let high = show.priceMax ?? show.priceMin
        guard let low, let high else { return nil }
        let lowText = Self.money(low)
        guard low != high else { return "$\(lowText)" }
        return "$\(lowText)–$\(Self.money(high))"
    }

    // MARK: - Status presentation

    /// Pill text for the ticket's status chip, or `nil` for ``ShowStatus/unknown``
    /// (rendered without a pill).
    public var statusPillText: String? {
        switch show.status {
        case .onSale: return "On Sale"
        case .soldOut: return "Sold Out"
        case .cancelled: return "Cancelled"
        case .free: return "Free"
        case .unknown: return nil
        }
    }

    /// Whether the ticket should render in its dimmed, cancelled treatment.
    public var isCancelled: Bool {
        show.status == .cancelled
    }

    // MARK: - Call to action

    /// The label for the outbound CTA button/link.
    public var ctaLabel: String {
        switch show.status {
        case .onSale: return "Get Tickets"
        case .free: return "RSVP"
        case .soldOut: return "See Venue Page"
        case .cancelled: return "See the venue's page"
        case .unknown: return "See Venue Page"
        }
    }

    /// The caption under the CTA, naming the venue where it helps. WXYC hands
    /// listeners off to the box office, so the copy makes clear where the tap goes.
    public var ctaCaption: String {
        let venue = show.venueName ?? "the venue"
        switch show.status {
        case .onSale, .unknown: return "Opens \(venue)'s event page"
        case .free: return "Free — opens the venue's event page"
        case .soldOut: return "Sold out here — \(venue) sometimes releases more."
        case .cancelled: return "This show has been cancelled."
        }
    }

    /// The compact tag shown on the matched feed row.
    public var feedTagText: String {
        switch show.status {
        case .onSale: return "Tickets"
        case .soldOut: return "Sold Out"
        case .cancelled: return "Cancelled"
        case .free: return "Free · RSVP"
        case .unknown: return "Details"
        }
    }

    /// The visual treatment for the feed-row tag, keyed off the same status that
    /// drives ``feedTagText``.
    public var feedTagStyle: FeedTagStyle {
        switch show.status {
        case .onSale: return .prominent
        case .free: return .free
        case .soldOut: return .muted
        case .cancelled: return .negative
        case .unknown: return .neutral
        }
    }

    /// The outbound CTA target — the venue's event page, falling back to the
    /// direct ticket link. `nil` when the show carries no link.
    public var ctaURL: URL? {
        show.ctaURL
    }

    // MARK: - Formatting helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .wxycStation
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .wxycStation
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    private static let weekdayFormatter = Self.stationFormatter("EEE")
    private static let dayNumberFormatter = Self.stationFormatter("d")
    private static let monthFormatter = Self.stationFormatter("MMM")

    /// Builds a station-zone, fixed-locale `DateFormatter` for a single field.
    private static func stationFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .wxycStation
        formatter.dateFormat = format
        return formatter
    }

    /// Formats a `HH:mm:ss` (or `HH:mm`) wall-clock string as `"7 PM"` /
    /// `"8:30 PM"`. Returns `nil` for an unparseable value.
    private static func wallClock(_ raw: String) -> String? {
        let parts = raw.split(separator: ":")
        guard let first = parts.first, let hour24 = Int(first), (0...23).contains(hour24) else {
            return nil
        }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let period = hour24 < 12 ? "AM" : "PM"
        return minute == 0 ? "\(hour12) \(period)" : String(format: "%d:%02d %@", hour12, minute, period)
    }

    /// Formats a dollar amount: whole dollars drop the decimal (`22`), otherwise
    /// two fraction digits (`12.50`).
    private static func money(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
