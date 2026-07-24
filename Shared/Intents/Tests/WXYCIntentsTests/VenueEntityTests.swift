//
//  VenueEntityTests.swift
//  WXYCIntents
//
//  Verifies that VenueEntity mirrors the source Venue's identity and
//  displayable fields (name, city/state), that the id-bridging initializer
//  guards a negative backend id rather than crashing on the
//  UInt64(negative) conversion, and that the CoreSpotlight attribute set
//  links back to the entity id, mirroring ConcertEntityTests.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Concerts
import ConcertsTesting
@testable import WXYCIntents
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

@Suite("VenueEntity")
struct VenueEntityTests {
    @Test("mirrors the source venue's id")
    func mirrorsSourceVenueID() throws {
        let venue = Venue.stub(id: 42)
        let entity = try #require(VenueEntity(venue: venue))

        #expect(entity.id.venueID == 42)
        #expect(entity.id == VenueID(venueID: 42))
    }

    @Test("round-trips its id through the EntityIdentifier string form")
    func roundTripsIdentifierViaString() throws {
        let entity = try #require(VenueEntity(venue: .stub(id: 12345)))
        let identifierString = entity.id.entityIdentifierString

        let decoded = VenueID.entityIdentifier(for: identifierString)

        #expect(decoded == entity.id)
    }

    @Test("fails to build an entity for a negative venue id rather than crashing")
    func failsForNegativeID() {
        let venue = Venue.stub(id: -1)

        #expect(VenueEntity(venue: venue) == nil)
    }

    @Test("EntityID.venueID bridges a constructed id back to the backend's Int id space")
    func venueIDBridgeRoundTrips() {
        let id = VenueID(venueID: 3)

        #expect(id?.venueID == 3)
    }

    @Test("VenueID(venueID:) rejects a negative backend id rather than trapping")
    func venueIDInitializerRejectsNegative() {
        #expect(VenueID(venueID: -1) == nil)
    }

    @Test("copies displayable metadata from the source venue")
    func copiesDisplayFields() throws {
        let venue = Venue.stub(id: 3, name: "Cat's Cradle", city: "Carrboro", state: "NC")
        let entity = try #require(VenueEntity(venue: venue))

        #expect(entity.name == "Cat's Cradle")
    }

    @Test("composes the subtitle as city, state")
    func subtitleComposesCityState() throws {
        let venue = Venue.stub(city: "Carrboro", state: "NC")
        let entity = try #require(VenueEntity(venue: venue))

        #expect(entity.subtitleText == "Carrboro, NC")
    }

    @Test("uses the venue name as the display representation title")
    func displayRepresentationUsesVenueName() throws {
        let venue = Venue.stub(name: "Motorco Music Hall")
        let entity = try #require(VenueEntity(venue: venue))

        let representation = entity.displayRepresentation
        let titleString = String(localized: representation.title)

        #expect(titleString == "Motorco Music Hall")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("populates the CoreSpotlight attribute set with Spotlight-visible metadata")
    func attributeSetCarriesSpotlightFields() throws {
        let venue = Venue.stub(id: 3, name: "Cat's Cradle", city: "Carrboro", state: "NC")
        let entity = try #require(VenueEntity(venue: venue))

        let set = entity.attributeSet

        #expect(set.title == "Cat's Cradle")
        #expect(set.contentDescription == entity.subtitleText)
        #expect(set.relatedUniqueIdentifier == "3")
    }
    #endif
}
