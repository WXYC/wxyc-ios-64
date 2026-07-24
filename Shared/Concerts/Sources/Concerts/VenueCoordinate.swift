//
//  VenueCoordinate.swift
//  Concerts
//
//  A bundled `Venue.slug -> (latitude, longitude)` table for the small,
//  stable set of Triangle-area venues WXYC's curated On Tour window already
//  names (see `VenueGrouping`). `Venue` carries no coordinates on the wire —
//  this is the v1 geo source `docs/ideas/spotlight-on-tour-entities.md`
//  recommends: zero-backend, zero-runtime, keyed by the stable `Venue.slug`
//  rather than the mutable `name`/`address`. A slug this table doesn't yet
//  carry resolves to `nil` — the caller (`VenueEntity.attributeSet`, Intents
//  package) degrades gracefully to a geo-less searchable name rather than
//  guessing a location or crashing.
//
//  Coordinates are geocoded from each venue's public street address
//  (OpenStreetMap Nominatim, matched as a named point of interest rather than
//  an interpolated address range) and are only as precise as that source —
//  good enough for Maps directions and a "near me" distance sort, not
//  survey-grade placement.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A geographic coordinate for a venue, in decimal degrees.
public struct VenueCoordinate: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Bundled venue geocoding, keyed by the backend's stable `Venue.slug`.
public enum VenueCoordinates {
    /// The coordinate for `slug`, or `nil` if this venue hasn't been added to
    /// the bundled table yet. Graceful by design — a miss means "no geo," not
    /// an error; extend ``bySlug`` as WXYC's curated window surfaces venues
    /// not yet listed here.
    public static func coordinate(forSlug slug: String) -> VenueCoordinate? {
        bySlug[slug]
    }

    /// The known Triangle-area venues, spanning `VenueGrouping`'s Chapel
    /// Hill–Carrboro / Durham / Saxapahaw regions. "Cat's Cradle Back Room"
    /// shares its parent room's coordinate — both are the same 300 E Main St
    /// building in Carrboro.
    private static let bySlug: [String: VenueCoordinate] = [
        "cats-cradle": VenueCoordinate(latitude: 35.9100634, longitude: -79.0684411),
        "cats-cradle-back": VenueCoordinate(latitude: 35.9100634, longitude: -79.0684411),
        "motorco": VenueCoordinate(latitude: 36.0035821, longitude: -78.9002707),
        "local-506": VenueCoordinate(latitude: 35.9102084, longitude: -79.0638330),
        "haw-river": VenueCoordinate(latitude: 35.9466083, longitude: -79.3190625),
    ]
}
