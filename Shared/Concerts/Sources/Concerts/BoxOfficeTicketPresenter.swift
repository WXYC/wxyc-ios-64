//
//  BoxOfficeTicketPresenter.swift
//  Concerts
//
//  Pure presentation logic for the Box Office ticket. Turns a ``Concert`` into
//  the display strings the SwiftUI view renders — date/time labels, price
//  string, and the per-status pill / CTA / caption copy — so all of that is unit
//  testable without a view. Copy mirrors the approved prototype
//  (docs/ideas/touring-shows-box-office.html).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The visual treatment for the compact feed-row tag, one per ``ShowStatus``.
/// Mirrors the prototype's four `.rtag` variants so the view maps a semantic
/// style to colors rather than switching on status itself.
public enum FeedTagStyle: Sendable, Equatable {
    /// On sale — the amber accent, drawing the eye toward an attendable show.
    case prominent
    /// Free — the teal accent.
    case free
    /// Sold out — dimmed; still linked, but no longer enticing.
    case muted
    /// Cancelled — a red, "dead" treatment.
    case negative
    /// Unknown / rescheduled — a plain, neutral chip.
    case neutral
}

/// The visual treatment for the poster-hero status pill, one per ``ShowStatus``.
/// Parallels ``FeedTagStyle`` — the view maps a semantic style to colors rather
/// than switching on status itself — but the poster palette differs (a solid
/// green "on sale", a coral "sold out") and splits `rescheduled` into its own
/// amber ``caution`` treatment instead of folding it into ``neutral``.
public enum StatusPillStyle: Sendable, Equatable {
    /// On sale — a solid green "go" accent.
    case prominent
    /// Free — the teal accent.
    case free
    /// Sold out — a coral accent; still linked, but no longer attendable.
    case muted
    /// Cancelled — a red, "dead" treatment.
    case negative
    /// Rescheduled — an amber "check the details" accent.
    case caution
    /// Unknown — a plain, neutral chip (rendered without a pill in practice,
    /// since ``BoxOfficeTicketPresenter/statusPillText`` is `nil` for it).
    case neutral
}

/// View-model for the Box Office ticket. Every property is a pure function of
/// the wrapped ``Concert``.
///
/// Date and time labels use the station time zone and a fixed `en_US_POSIX`
/// locale, the same determinism choice made for `Breakpoint.hourLabel`, so the
/// rendered day/time never shifts with the device's zone or locale.
public struct BoxOfficeTicketPresenter: Sendable, Equatable {
    public let show: Concert

    public init(_ show: Concert) {
        self.show = show
    }

    // MARK: - Date

    /// Full date label, e.g. `"Sat, Aug 1"`.
    public var dateLabel: String {
        Self.dateFormatter.string(from: show.startsOn)
    }

    /// Compact, upper-cased date for the feed-row stub, e.g. `"SAT AUG 1"`.
    public var compactDateLabel: String {
        Self.compactDateFormatter.string(from: show.startsOn).uppercased()
    }

    /// Upper-cased weekday for the ticket stub's date block, e.g. `"SAT"`.
    public var stubWeekday: String {
        Self.weekdayFormatter.string(from: show.startsOn).uppercased()
    }

    /// Day-of-month for the ticket stub's date block, e.g. `"1"`.
    public var stubDayNumber: String {
        Self.dayNumberFormatter.string(from: show.startsOn)
    }

    /// Upper-cased month for the ticket stub's date block, e.g. `"AUG"`.
    public var stubMonth: String {
        Self.monthFormatter.string(from: show.startsOn).uppercased()
    }

    /// A stable, faux "admit one" serial derived from the concert id (`"WX-4821"`).
    /// Cosmetic keepsake detail; deterministic so the same concert always prints
    /// the same number.
    public var ticketSerial: String {
        "WX-\(show.id)"
    }

    // MARK: - Time

    /// A single time label combining whichever of doors/show times are present:
    /// `"Doors 7 PM · Show 8 PM"`, `"Show 8 PM"`, `"Doors 7 PM"`, or `nil` when
    /// neither is known.
    ///
    /// Derived from the ``Concert/doorsAt``/``Concert/startsAt`` instants,
    /// formatted in the station (venue) zone — the printed time is the venue's
    /// local wall-clock.
    public var timeLabel: String? {
        let doors = doorsLabel
        let showTime = showLabel
        switch (doors, showTime) {
        case let (doors?, show?): return "Doors \(doors) · Show \(show)"
        case let (nil, show?): return "Show \(show)"
        case let (doors?, nil): return "Doors \(doors)"
        case (nil, nil): return nil
        }
    }

    /// The doors time on its own (`"7 PM"`), for a dedicated stat cell. `nil`
    /// when ``Concert/doorsAt`` is absent.
    public var doorsLabel: String? {
        show.doorsAt.map(Self.wallClock)
    }

    /// The set/show time on its own (`"8 PM"`), for a dedicated stat cell. `nil`
    /// when ``Concert/startsAt`` is absent.
    public var showLabel: String? {
        show.startsAt.map(Self.wallClock)
    }

    // MARK: - Price

    /// The price string: `"Free"` for a free show, `"$22"` for a single price,
    /// `"$22–$25"` for a range (en dash), or `nil` when unpriced and not free.
    ///
    /// Free detection has two signals: the modeled-but-unemitted ``ShowStatus/free``
    /// case, and — the one the live backend actually uses — `price_min == 0`. The
    /// `Concert` schema documents "Free events carry price_min = 0", and its status
    /// enum has no `free` value, so a genuinely-free show arrives as e.g.
    /// `{status: "on_sale", price_min: 0}`. Without the `priceMin == 0` check it
    /// would fall through to the numeric branch and render `"$0"`.
    public var priceLabel: String? {
        if show.status == .free { return "Free" }
        // Free signal is price_min == 0, but only when there is no nonzero upper
        // bound — otherwise a genuine "$0–$25" range would collapse to "Free".
        if show.priceMin == 0, (show.priceMax ?? 0) == 0 { return "Free" }
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
        case .rescheduled: return "Rescheduled"
        case .free: return "Free"
        case .unknown: return nil
        }
    }

    /// Whether the ticket should render in its dimmed, cancelled treatment.
    public var isCancelled: Bool {
        show.status == .cancelled
    }

    // MARK: - Poster detail

    /// The compact credit line printed over the poster hero: compact date and
    /// city only (e.g. `"SAT AUG 1 · Carrboro"`). State and address are
    /// deliberately excluded — the tucked ticket carries the full "where".
    public var heroCreditLine: String {
        "\(compactDateLabel) · \(show.venue.city)"
    }

    /// `"with <support> · <age>"`, omitting whichever pieces are absent; `nil`
    /// when neither is present. The Box Office ticket and the poster hero share
    /// this one tested string (an empty age string reads as absent).
    public var subline: String? {
        var pieces: [String] = []
        if !show.supportingArtistsRaw.isEmpty {
            pieces.append("with \(show.supportingArtistsRaw.joined(separator: ", "))")
        }
        if let age = show.ageRestriction, !age.isEmpty { pieces.append(age) }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " · ")
    }

    /// The plain-text venue search query — the venue name, then the street
    /// address when present, then city/state, with empty components skipped so
    /// the query is never blank. One string shared by ``directionsURL`` and the
    /// detail's map geocoding, so the marker and the Directions action always
    /// resolve the same place. The venue carries no coordinates on the wire, so
    /// this query is the map's only location source.
    public var venueSearchQuery: String {
        var parts = [show.venue.name]
        if let address = show.venue.address, !address.isEmpty { parts.append(address) }
        if !show.venue.city.isEmpty { parts.append(show.venue.city) }
        if !show.venue.state.isEmpty { parts.append(show.venue.state) }
        return parts.joined(separator: ", ")
    }

    /// An Apple Maps search URL for the venue, backing the detail's "Directions"
    /// action — ``venueSearchQuery`` wrapped in a maps.apple.com search link.
    /// Built via `URLComponents` so it is correctly percent-encoded.
    public var directionsURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.queryItems = [URLQueryItem(name: "q", value: venueSearchQuery)]
        return components.url
    }

    // MARK: - Call to action

    /// Whether the CTA resolves to the venue's own event page
    /// (``Concert/eventURL``) rather than the ticket-seller fallback. Drives
    /// the "venue page" vs "ticket page" wording in ``ctaLabel`` and
    /// ``ctaCaption`` so the copy never claims a venue page the tap won't open.
    private var ctaTargetsVenuePage: Bool {
        show.eventURL != nil
    }

    /// The label for the outbound CTA button/link, worded for where the tap
    /// actually goes (venue event page vs ticket seller).
    public var ctaLabel: String {
        switch show.status {
        case .onSale: return "Get Tickets"
        case .free: return "RSVP"
        case .soldOut: return ctaTargetsVenuePage ? "See Venue Page" : "See Ticket Page"
        case .rescheduled: return "Get Tickets"
        case .cancelled: return ctaTargetsVenuePage ? "See the venue's page" : "See the ticket page"
        case .unknown: return ctaTargetsVenuePage ? "See Venue Page" : "See Ticket Page"
        }
    }

    /// The caption under the CTA, naming the venue where it helps. WXYC hands
    /// listeners off to the box office, so the copy makes clear where the tap
    /// goes — the venue's event page when one is known, else the ticket page.
    public var ctaCaption: String {
        let venue = show.venue.name
        switch show.status {
        case .onSale, .unknown:
            return ctaTargetsVenuePage ? "Opens \(venue)'s event page" : "Opens the ticket page"
        case .rescheduled:
            return ctaTargetsVenuePage ? "Rescheduled — opens \(venue)'s event page" : "Rescheduled — opens the ticket page"
        case .free:
            return ctaTargetsVenuePage ? "Free — opens the venue's event page" : "Free — opens the RSVP page"
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
        case .rescheduled: return "Rescheduled"
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
        case .rescheduled: return .neutral
        case .unknown: return .neutral
        }
    }

    /// The visual treatment for the poster-hero status pill, keyed off the same
    /// status that drives ``statusPillText`` — the poster counterpart to
    /// ``feedTagStyle``.
    public var statusPillStyle: StatusPillStyle {
        switch show.status {
        case .onSale: return .prominent
        case .free: return .free
        case .soldOut: return .muted
        case .cancelled: return .negative
        case .rescheduled: return .caution
        case .unknown: return .neutral
        }
    }

    /// The outbound CTA target — the venue's own event page when known, else
    /// the direct ticket link. `nil` when the concert carries no link.
    public var ctaURL: URL? {
        show.ctaURL
    }

    // MARK: - Formatting helpers

    private static let dateFormatter = Self.stationFormatter("EEE, MMM d")
    private static let compactDateFormatter = Self.stationFormatter("EEE MMM d")
    private static let weekdayFormatter = Self.stationFormatter("EEE")
    private static let dayNumberFormatter = Self.stationFormatter("d")
    private static let monthFormatter = Self.stationFormatter("MMM")

    /// Station-zone, fixed-locale time formatter producing `"7 PM"` on the hour
    /// and `"8:30 PM"` otherwise. Built from two formats selected at call time so
    /// on-the-hour times drop the `:00`.
    private static let hourOnlyTimeFormatter = Self.stationFormatter("h a")
    private static let hourMinuteTimeFormatter = Self.stationFormatter("h:mm a")

    /// Builds a station-zone, fixed-locale `DateFormatter` for a single format.
    private static func stationFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .wxycStation
        formatter.dateFormat = format
        return formatter
    }

    /// Formats an instant as the venue's wall-clock time (`"7 PM"` /
    /// `"8:30 PM"`), dropping the minutes when the time falls on the hour.
    private static func wallClock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        let minute = calendar.component(.minute, from: date)
        let formatter = minute == 0 ? hourOnlyTimeFormatter : hourMinuteTimeFormatter
        return formatter.string(from: date)
    }

    /// Formats a dollar amount: whole dollars drop the decimal (`22`), otherwise
    /// two fraction digits (`12.50`).
    private static func money(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
