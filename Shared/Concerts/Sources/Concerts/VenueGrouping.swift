//
//  VenueGrouping.swift
//  Concerts
//
//  Groups the distinct venues present in a fetched concert window into the
//  city/region sections the filter sheet's venue checklist renders. Grouping is
//  data-driven — a venue in a city outside the known Triangle set still gets its
//  own section rather than disappearing — with the well-known Triangle regions
//  pinned to a preferred order.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A city/region section of venues for the filter sheet's grouped checklist.
public struct VenueRegionGroup: Sendable, Equatable, Identifiable {

    /// The display region (a city name, or a coalesced label like
    /// "Chapel Hill–Carrboro").
    public let region: String

    /// The venues in this region, sorted by name.
    public let venues: [Venue]

    public var id: String { region }

    public init(region: String, venues: [Venue]) {
        self.region = region
        self.venues = venues
    }
}

/// Groups venues by region for the filter sheet.
public enum VenueGrouping {

    /// The Triangle regions in the order the sheet lists them. Regions not in
    /// this list (e.g. Pittsboro, Hillsborough) sort alphabetically after these.
    private static let preferredRegionOrder = [
        "Chapel Hill–Carrboro",
        "Durham",
        "Raleigh",
        "Saxapahaw",
    ]

    /// Maps a venue's `city` to its display region. Chapel Hill and Carrboro —
    /// one contiguous scene straddling the town line — collapse into a single
    /// section; every other city is its own region.
    public static func region(forCity city: String) -> String {
        switch city {
        case "Chapel Hill", "Carrboro": "Chapel Hill–Carrboro"
        default: city
        }
    }

    /// Groups the distinct venues (de-duplicated by id) into region sections,
    /// regions in preferred-then-alphabetical order and venues sorted by name.
    public static func groupedByRegion(_ venues: [Venue]) -> [VenueRegionGroup] {
        var seen = Set<Int>()
        let distinct = venues.filter { seen.insert($0.id).inserted }

        return Dictionary(grouping: distinct) { region(forCity: $0.city) }
            .map { region, venues in
                VenueRegionGroup(region: region, venues: venues.sorted { $0.name < $1.name })
            }
            .sorted(by: regionOrdering)
    }

    /// Orders regions: those in ``preferredRegionOrder`` first (in that order),
    /// then any others alphabetically.
    private static func regionOrdering(_ lhs: VenueRegionGroup, _ rhs: VenueRegionGroup) -> Bool {
        let lhsIndex = preferredRegionOrder.firstIndex(of: lhs.region)
        let rhsIndex = preferredRegionOrder.firstIndex(of: rhs.region)
        switch (lhsIndex, rhsIndex) {
        case let (left?, right?): return left < right
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return lhs.region < rhs.region
        }
    }
}
