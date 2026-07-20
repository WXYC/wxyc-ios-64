//
//  ConcertCalendarEvent.swift
//  Concerts
//
//  A pure value type describing the calendar entry for a ``Concert`` (#538). It
//  holds exactly the fields the view layer copies into an `EKEvent`, so every
//  date decision — timed vs. all-day, the default block duration, the
//  station-zone doors note, the geocodable location — is derived and unit-tested
//  here rather than in an EventKit-bound, device-only view.
//
//  Date discipline mirrors the rest of the package (see `TimeZone+Station`): the
//  wall-clock doors label and the all-day day boundary are pinned to the station
//  (venue) zone, never the device's, so the entry reads the same regardless of
//  where the listener adds it.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The calendar entry for a concert, ready to be copied into an `EKEvent`.
///
/// Built entirely from a ``Concert``:
///
/// - **Timed** — when ``Concert/startsAt`` is present, a fixed-length event
///   starting at that instant. Concerts carry no end time, so the entry blocks
///   ``defaultDuration`` (a typical headline set plus openers).
/// - **All-day** — when ``Concert/startsAt`` is absent, a single all-day event on
///   ``Concert/startsOn`` (the station-zone calendar day). Whether or not doors is
///   known, the start keys off `starts_at` only — a doors-only show is still
///   all-day, with the doors time preserved in ``notes``.
public struct ConcertCalendarEvent: Sendable, Equatable {

    /// The event title — the headline billing (``Concert/headlineName``).
    public let title: String

    /// The event start. The exact ``Concert/startsAt`` instant for a timed event;
    /// the station-zone start of ``Concert/startsOn`` for an all-day event.
    public let startDate: Date

    /// The event end. ``startDate`` plus ``defaultDuration`` for a timed event;
    /// equal to ``startDate`` (a single day) for an all-day event.
    public let endDate: Date

    /// Whether this is an all-day event (no known start instant).
    public let isAllDay: Bool

    /// The geocodable venue line (name, street, city, state), or `nil` only if the
    /// venue somehow carried no describable location. Empty components are skipped.
    public let location: String?

    /// Supplementary notes — the doors time (`"Doors 7 PM"`) when
    /// ``Concert/doorsAt`` is known, else `nil`.
    public let notes: String?

    /// The canonical public share link (``Concert/shareURL``), so the calendar
    /// entry deep-links back to the show.
    public let url: URL

    /// The time zone the entry is expressed in — always the station (venue) zone,
    /// so a timed event shows the venue's local wall-clock even for a listener in
    /// another zone.
    public let timeZone: TimeZone

    /// How long a timed event blocks when the concert carries no end instant —
    /// three hours, a typical doors-to-encore span.
    public static let defaultDuration: TimeInterval = 3 * 60 * 60

    /// Builds the calendar entry for `concert`.
    public init(_ concert: Concert) {
        self.title = concert.headlineName
        self.location = Self.location(for: concert.venue)
        self.notes = concert.doorsAt.map { "Doors \($0.stationWallClock())" }
        self.url = concert.shareURL
        self.timeZone = .wxycStation

        if let startsAt = concert.startsAt {
            self.isAllDay = false
            self.startDate = startsAt
            self.endDate = startsAt.addingTimeInterval(Self.defaultDuration)
        } else {
            self.isAllDay = true
            let day = Calendar.wxycStation.startOfDay(for: concert.startsOn)
            self.startDate = day
            self.endDate = day
        }
    }

    // MARK: - Derivations

    /// The geocodable location line: venue name, then street address, then city,
    /// then state, joining only the non-empty parts — the same "where" string the
    /// map search uses, so the calendar pin and the in-app map resolve the same
    /// place.
    private static func location(for venue: Venue) -> String? {
        var parts = [venue.name]
        if let address = venue.address, !address.isEmpty { parts.append(address) }
        if !venue.city.isEmpty { parts.append(venue.city) }
        if !venue.state.isEmpty { parts.append(venue.state) }
        let line = parts.joined(separator: ", ")
        return line.isEmpty ? nil : line
    }
}
