//
//  VenueCoordinatesTests.swift
//  ConcertsTests
//
//  Verifies the bundled slug -> coordinate lookup that backs VenueEntity's
//  geo affordances (OT-C4): a slug in the table resolves to a coordinate, an
//  unknown slug resolves to nil rather than crashing or fabricating a value.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts

@Suite("VenueCoordinates")
struct VenueCoordinatesTests {
    @Test("resolves a known slug to its bundled coordinate")
    func resolvesKnownSlug() throws {
        let coordinate = try #require(VenueCoordinates.coordinate(forSlug: "cats-cradle"))

        #expect(coordinate.latitude == 35.9100634)
        #expect(coordinate.longitude == -79.0684411)
    }

    @Test("resolves every known WXYC-representative venue slug in the bundled table", arguments: [
        "cats-cradle",
        "cats-cradle-back",
        "motorco",
        "local-506",
        "haw-river",
    ])
    func resolvesEveryBundledSlug(_ slug: String) {
        #expect(VenueCoordinates.coordinate(forSlug: slug) != nil)
    }

    @Test("returns nil for a slug outside the bundled table, rather than guessing")
    func returnsNilForUnknownSlug() {
        #expect(VenueCoordinates.coordinate(forSlug: "some-venue-not-yet-added") == nil)
    }

    @Test("returns nil for an empty slug")
    func returnsNilForEmptySlug() {
        #expect(VenueCoordinates.coordinate(forSlug: "") == nil)
    }
}
