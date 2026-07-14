//
//  ConcertFilterState.swift
//  Concerts
//
//  The client-side facet state for the Touring Soon tab. Holds the user's filter
//  selections and evaluates them as pure predicates over an already-fetched
//  window of concerts — no refetch on change (the triangle-shows recipe). Every
//  predicate is a value-in/value-out function so the model can recompute the
//  filtered projection synchronously on the main actor.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The facet selections applied to the fetched concert window.
///
/// All facets combine with AND. The relative date windows are evaluated against
/// an injected `now` (rather than reading the clock internally) so ``matches(_:now:)``
/// stays pure and deterministic under test.
public struct ConcertFilterState: Sendable, Equatable {

    /// The cumulative date filter. Each window is a superset of the previous:
    /// `tonight ⊆ thisWeekend ⊆ next7Days ⊆ all`. All windows start at "today"
    /// (the station-local calendar day of `now`); they differ only in the upper
    /// bound, so "This weekend" on a Tuesday means "between now and the end of
    /// the coming weekend", not "only Fri–Sun".
    public enum DateWindow: Sendable, Equatable, Hashable, CaseIterable {
        /// No date bound.
        case all
        /// Today only.
        case tonight
        /// Today through the coming Sunday (inclusive).
        case thisWeekend
        /// Today through today + 6 days (inclusive).
        case next7Days

        /// The short display label, shared by the filter sheet's segmented control
        /// and the applied-filter pills.
        public var title: String {
            switch self {
            case .all: "All"
            case .tonight: "Tonight"
            case .thisWeekend: "Weekend"
            case .next7Days: "7 Days"
            }
        }
    }

    /// The selected date window.
    public var dateWindow: DateWindow

    /// Venue ids to include. **Empty means all venues** — unchecking every venue
    /// restores the full list rather than producing a self-inflicted empty state.
    public var selectedVenueIDs: Set<Int>

    /// When `true`, keep only shows with an advertised `price_min` of 0. An
    /// unknown (`nil`) price is *not* treated as free.
    public var freeOnly: Bool

    /// When `true`, hide only shows we can prove are age-restricted; shows whose
    /// policy is all-ages or simply unknown remain visible.
    public var allAgesOnly: Bool

    public init(
        dateWindow: DateWindow = .all,
        selectedVenueIDs: Set<Int> = [],
        freeOnly: Bool = false,
        allAgesOnly: Bool = false
    ) {
        self.dateWindow = dateWindow
        self.selectedVenueIDs = selectedVenueIDs
        self.freeOnly = freeOnly
        self.allAgesOnly = allAgesOnly
    }

    // MARK: - Active-facet accounting

    /// The number of engaged facet *groups* (not selections) — the value shown
    /// in the Filter button's badge. A multi-venue selection counts once.
    public var activeFacetCount: Int {
        var count = 0
        if dateWindow != .all { count += 1 }
        if !selectedVenueIDs.isEmpty { count += 1 }
        if freeOnly { count += 1 }
        if allAgesOnly { count += 1 }
        return count
    }

    /// Whether any facet narrows the fetched window.
    public var isActive: Bool { activeFacetCount > 0 }

    /// Clears every facet back to the unfiltered default.
    public mutating func reset() {
        self = ConcertFilterState()
    }

    // MARK: - Predicate

    /// Whether `concert` passes every engaged facet, evaluated relative to `now`
    /// (station-local) for the date window.
    public func matches(_ concert: Concert, now: Date) -> Bool {
        matchesDateWindow(concert, now: now)
            && matchesVenue(concert)
            && matchesFree(concert)
            && matchesAllAges(concert)
    }

    private func matchesDateWindow(_ concert: Concert, now: Date) -> Bool {
        guard dateWindow != .all else { return true }
        let calendar = Self.stationCalendar
        let today = calendar.startOfDay(for: now)
        let concertDay = calendar.startOfDay(for: concert.startsOn)
        guard concertDay >= today else { return false }
        guard let upperBound = Self.upperBound(for: dateWindow, today: today, calendar: calendar) else {
            return true
        }
        return concertDay <= upperBound
    }

    private func matchesVenue(_ concert: Concert) -> Bool {
        selectedVenueIDs.isEmpty || selectedVenueIDs.contains(concert.venue.id)
    }

    private func matchesFree(_ concert: Concert) -> Bool {
        guard freeOnly else { return true }
        return concert.priceMin == 0
    }

    private func matchesAllAges(_ concert: Concert) -> Bool {
        guard allAgesOnly else { return true }
        // Hide only a proven restriction; unknown and all-ages both stay visible.
        if case .restricted = AgeRestrictionCategory(rawText: concert.ageRestriction) {
            return false
        }
        return true
    }

    // MARK: - Date math (station zone)

    private static var stationCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .wxycStation
        return calendar
    }

    /// The inclusive upper-bound calendar day for a window, or `nil` for `.all`.
    private static func upperBound(for window: DateWindow, today: Date, calendar: Calendar) -> Date? {
        switch window {
        case .all: nil
        case .tonight: today
        case .thisWeekend: comingSunday(onOrAfter: today, calendar: calendar)
        case .next7Days: calendar.date(byAdding: .day, value: 6, to: today) ?? today
        }
    }

    /// The first Sunday on or after `day`. Returns `day` itself when it is a
    /// Sunday, so the weekend window collapses to today at week's end.
    private static func comingSunday(onOrAfter day: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday (Gregorian)
        let daysUntilSunday = (8 - weekday) % 7
        return calendar.date(byAdding: .day, value: daysUntilSunday, to: day) ?? day
    }
}
