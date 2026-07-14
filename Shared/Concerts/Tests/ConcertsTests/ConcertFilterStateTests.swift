//
//  ConcertFilterStateTests.swift
//  Concerts
//
//  Facet-by-facet and combined coverage for the client-side concert filter. All
//  predicates are pure and evaluated against an injected `now` so the relative
//  date windows are deterministic in tests.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

/// Builds a station-zone (`America/New_York`) instant at the given hour on the
/// given calendar day, so "today" is unambiguous regardless of the host zone.
private func stationDay(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
}

/// A concert whose `starts_on` is the given station calendar day.
private func concert(on year: Int, _ month: Int, _ day: Int,
                     venue: Venue = .stub(),
                     priceMin: Double? = 20,
                     ageRestriction: String? = "All Ages") -> Concert {
    Concert.stub(
        venue: venue,
        startsOn: stationDay(year, month, day, hour: 0),
        priceMin: priceMin,
        ageRestriction: ageRestriction
    )
}

@Suite("ConcertFilterState")
struct ConcertFilterStateTests {

    // MARK: - Date windows (now = Saturday 2026-08-01)

    // 2026-08-01 is a Saturday; the coming Sunday is 2026-08-02.
    private static let saturdayNow = stationDay(2026, 8, 1)

    @Test("`.all` matches every date, including far-future")
    func allWindowMatchesEverything() {
        let filter = ConcertFilterState(dateWindow: .all)
        #expect(filter.matches(concert(on: 2026, 8, 1), now: Self.saturdayNow))
        #expect(filter.matches(concert(on: 2026, 12, 31), now: Self.saturdayNow))
    }

    @Test("`.tonight` matches only today")
    func tonightWindow() {
        let filter = ConcertFilterState(dateWindow: .tonight)
        #expect(filter.matches(concert(on: 2026, 8, 1), now: Self.saturdayNow))      // today
        #expect(!filter.matches(concert(on: 2026, 8, 2), now: Self.saturdayNow))     // tomorrow
        #expect(!filter.matches(concert(on: 2026, 7, 31), now: Self.saturdayNow))    // yesterday
    }

    @Test("`.thisWeekend` is cumulative: today through the coming Sunday")
    func thisWeekendWindowFromSaturday() {
        let filter = ConcertFilterState(dateWindow: .thisWeekend)
        #expect(filter.matches(concert(on: 2026, 8, 1), now: Self.saturdayNow))      // Sat (today)
        #expect(filter.matches(concert(on: 2026, 8, 2), now: Self.saturdayNow))      // Sun (coming Sunday)
        #expect(!filter.matches(concert(on: 2026, 8, 3), now: Self.saturdayNow))     // Mon — past the weekend
        #expect(!filter.matches(concert(on: 2026, 7, 31), now: Self.saturdayNow))    // yesterday
    }

    @Test("`.thisWeekend` on a Sunday collapses to just today")
    func thisWeekendWindowFromSunday() {
        let sundayNow = stationDay(2026, 8, 2)                                        // Sunday
        let filter = ConcertFilterState(dateWindow: .thisWeekend)
        #expect(filter.matches(concert(on: 2026, 8, 2), now: sundayNow))             // Sun (today)
        #expect(!filter.matches(concert(on: 2026, 8, 3), now: sundayNow))            // Mon
    }

    @Test("`.next7Days` is cumulative: today through today+6, exclusive of day 7")
    func next7DaysWindow() {
        let filter = ConcertFilterState(dateWindow: .next7Days)
        #expect(filter.matches(concert(on: 2026, 8, 1), now: Self.saturdayNow))      // today
        #expect(filter.matches(concert(on: 2026, 8, 7), now: Self.saturdayNow))      // today+6 (boundary)
        #expect(!filter.matches(concert(on: 2026, 8, 8), now: Self.saturdayNow))     // today+7
        #expect(!filter.matches(concert(on: 2026, 7, 31), now: Self.saturdayNow))    // yesterday
    }

    @Test("`.next7Days` spans the fall-back DST boundary without drift")
    func next7DaysAcrossDSTBoundary() {
        // US DST ends Sunday 2026-11-01. A 7-day window from Wednesday 2026-10-28
        // must still end on 2026-11-03 (today+6) despite the 25-hour day — proving
        // the window is computed on calendar days, not fixed 24-hour offsets.
        let octoberNow = stationDay(2026, 10, 28)
        let filter = ConcertFilterState(dateWindow: .next7Days)
        #expect(filter.matches(concert(on: 2026, 10, 28), now: octoberNow))          // today
        #expect(filter.matches(concert(on: 2026, 11, 3), now: octoberNow))           // today+6, across DST
        #expect(!filter.matches(concert(on: 2026, 11, 4), now: octoberNow))          // today+7
    }

    // MARK: - Date-window titles

    @Test("Each date window exposes its short display title")
    func dateWindowTitles() {
        #expect(ConcertFilterState.DateWindow.all.title == "All")
        #expect(ConcertFilterState.DateWindow.tonight.title == "Tonight")
        #expect(ConcertFilterState.DateWindow.thisWeekend.title == "Weekend")
        #expect(ConcertFilterState.DateWindow.next7Days.title == "7 Days")
    }

    // MARK: - Venue facet

    @Test("Empty venue selection matches all venues")
    func emptyVenueSelectionMatchesAll() {
        let filter = ConcertFilterState(selectedVenueIDs: [])
        #expect(filter.matches(concert(on: 2026, 8, 1, venue: .stub(id: 3)), now: Self.saturdayNow))
        #expect(filter.matches(concert(on: 2026, 8, 1, venue: .stub(id: 9)), now: Self.saturdayNow))
    }

    @Test("A venue selection matches only the selected venue ids")
    func venueSelectionFilters() {
        let filter = ConcertFilterState(selectedVenueIDs: [3, 5])
        #expect(filter.matches(concert(on: 2026, 8, 1, venue: .stub(id: 3)), now: Self.saturdayNow))
        #expect(filter.matches(concert(on: 2026, 8, 1, venue: .stub(id: 5)), now: Self.saturdayNow))
        #expect(!filter.matches(concert(on: 2026, 8, 1, venue: .stub(id: 9)), now: Self.saturdayNow))
    }

    // MARK: - Free facet

    @Test("Free-only matches a price_min of 0 and excludes priced / unpriced shows")
    func freeOnlyFacet() {
        let filter = ConcertFilterState(freeOnly: true)
        #expect(filter.matches(concert(on: 2026, 8, 1, priceMin: 0), now: Self.saturdayNow))
        #expect(!filter.matches(concert(on: 2026, 8, 1, priceMin: 20), now: Self.saturdayNow))
        #expect(!filter.matches(concert(on: 2026, 8, 1, priceMin: nil), now: Self.saturdayNow)) // unknown ≠ free
    }

    // MARK: - All-ages facet

    @Test("All-ages-only hides only provably-restricted shows")
    func allAgesFacet() {
        let filter = ConcertFilterState(allAgesOnly: true)
        #expect(filter.matches(concert(on: 2026, 8, 1, ageRestriction: "All Ages"), now: Self.saturdayNow))
        #expect(filter.matches(concert(on: 2026, 8, 1, ageRestriction: nil), now: Self.saturdayNow))      // unknown stays
        #expect(filter.matches(concert(on: 2026, 8, 1, ageRestriction: "Ask venue"), now: Self.saturdayNow)) // unknown stays
        #expect(filter.matches(concert(on: 2026, 8, 1, ageRestriction: "0+"), now: Self.saturdayNow))     // "0+" = all-ages, stays
        #expect(!filter.matches(concert(on: 2026, 8, 1, ageRestriction: "18+"), now: Self.saturdayNow))   // restricted hidden
    }

    // MARK: - Combined facets (AND)

    @Test("Facets combine with AND")
    func facetsCombine() {
        let filter = ConcertFilterState(
            dateWindow: .next7Days,
            selectedVenueIDs: [3],
            freeOnly: true,
            allAgesOnly: true
        )
        // Satisfies every facet.
        #expect(filter.matches(
            concert(on: 2026, 8, 2, venue: .stub(id: 3), priceMin: 0, ageRestriction: "All Ages"),
            now: Self.saturdayNow
        ))
        // Fails the venue facet alone.
        #expect(!filter.matches(
            concert(on: 2026, 8, 2, venue: .stub(id: 9), priceMin: 0, ageRestriction: "All Ages"),
            now: Self.saturdayNow
        ))
        // Fails the free facet alone.
        #expect(!filter.matches(
            concert(on: 2026, 8, 2, venue: .stub(id: 3), priceMin: 15, ageRestriction: "All Ages"),
            now: Self.saturdayNow
        ))
    }

    // MARK: - Active-facet accounting (badge / pills)

    @Test("A default filter is inactive")
    func defaultFilterInactive() {
        let filter = ConcertFilterState()
        #expect(!filter.isActive)
        #expect(filter.activeFacetCount == 0)
    }

    @Test("activeFacetCount counts each engaged facet group once")
    func activeFacetCount() {
        #expect(ConcertFilterState(dateWindow: .tonight).activeFacetCount == 1)
        #expect(ConcertFilterState(selectedVenueIDs: [1, 2, 3]).activeFacetCount == 1) // one group, not three
        #expect(ConcertFilterState(
            dateWindow: .tonight,
            selectedVenueIDs: [1],
            freeOnly: true,
            allAgesOnly: true
        ).activeFacetCount == 4)
    }

    @Test("reset() clears every facet")
    func resetClearsFacets() {
        var filter = ConcertFilterState(dateWindow: .tonight, selectedVenueIDs: [1], freeOnly: true, allAgesOnly: true)
        filter.reset()
        #expect(filter == ConcertFilterState())
        #expect(!filter.isActive)
    }

    // MARK: - Venue grouping by region

    @Test("Groups distinct venues by region, coalescing Chapel Hill + Carrboro")
    func venueGroupingByRegion() {
        let catsCradle = Venue.stub(id: 3, slug: "cats-cradle", name: "Cat's Cradle", city: "Carrboro")
        let local506 = Venue.stub(id: 1, slug: "local-506", name: "Local 506", city: "Chapel Hill")
        let cats9 = Venue.stub(id: 5, slug: "cats-cradle-back", name: "Cat's Cradle Back Room", city: "Carrboro")
        let motorco = Venue.stub(id: 7, slug: "motorco", name: "Motorco", city: "Durham")
        let haw = Venue.stub(id: 9, slug: "haw-river", name: "Haw River Ballroom", city: "Saxapahaw")

        let groups = VenueGrouping.groupedByRegion([catsCradle, local506, cats9, motorco, haw])

        // Chapel Hill–Carrboro first (preferred order), then Durham, then Saxapahaw.
        #expect(groups.map(\.region) == ["Chapel Hill–Carrboro", "Durham", "Saxapahaw"])
        // The CH–Carrboro region holds all three of its venues, sorted by name.
        #expect(groups[0].venues.map(\.name) == ["Cat's Cradle", "Cat's Cradle Back Room", "Local 506"])
    }

    @Test("Grouping de-duplicates repeated venues and keeps unknown cities")
    func venueGroupingDeduplicatesAndKeepsUnknownCities() {
        let cradleA = Venue.stub(id: 3, city: "Carrboro")
        let cradleB = Venue.stub(id: 3, city: "Carrboro") // same id, duplicate
        let pittsboro = Venue.stub(id: 11, slug: "haw-river-ballroom", name: "The Plant", city: "Pittsboro")

        let groups = VenueGrouping.groupedByRegion([cradleA, cradleB, pittsboro])

        // Duplicate venue id collapses to one entry.
        #expect(groups.first(where: { $0.region == "Chapel Hill–Carrboro" })?.venues.count == 1)
        // An unlisted city still appears (alphabetically after the preferred set) rather than vanishing.
        #expect(groups.map(\.region) == ["Chapel Hill–Carrboro", "Pittsboro"])
    }
}
