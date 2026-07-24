//
//  ConcertEntityTests.swift
//  WXYCIntents
//
//  Verifies that ConcertEntity mirrors the source Concert's identity and
//  displayable fields (headliner, venue, date), that the id-bridging
//  initializer guards a negative backend id rather than crashing on the
//  UInt64(negative) conversion, and that the CoreSpotlight attribute set
//  links back to the entity id for OpenConcert routing.
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

@Suite("ConcertEntity")
struct ConcertEntityTests {
    @Test("mirrors the source concert's id")
    func mirrorsSourceConcertID() throws {
        let concert = Concert.stub(id: 42)
        let entity = try #require(ConcertEntity(concert: concert))

        #expect(entity.id.concertID == 42)
        #expect(entity.id == ConcertID(concertID: 42))
    }

    @Test("round-trips its id through the EntityIdentifier string form")
    func roundTripsIdentifierViaString() throws {
        let entity = try #require(ConcertEntity(concert: .stub(id: 12345)))
        let identifierString = entity.id.entityIdentifierString

        let decoded = ConcertID.entityIdentifier(for: identifierString)

        #expect(decoded == entity.id)
    }

    @Test("fails to build an entity for a negative concert id rather than crashing")
    func failsForNegativeID() {
        let concert = Concert.stub(id: -1)

        #expect(ConcertEntity(concert: concert) == nil)
    }

    @Test("EntityID.concertID bridges a constructed id back to the backend's Int id space")
    func concertIDBridgeRoundTrips() {
        let id = ConcertID(concertID: 4821)

        #expect(id?.concertID == 4821)
    }

    @Test("ConcertID(concertID:) rejects a negative backend id rather than trapping")
    func concertIDInitializerRejectsNegative() {
        #expect(ConcertID(concertID: -1) == nil)
    }

    @Test("copies displayable metadata from the source concert")
    func copiesDisplayFields() throws {
        let concert = Concert.stub(
            id: 7,
            venue: .stub(name: "Cat's Cradle", city: "Carrboro", state: "NC"),
            headliningArtistRaw: "Jessica Pratt"
        )
        let entity = try #require(ConcertEntity(concert: concert))

        #expect(entity.headlinerName == "Jessica Pratt")
        #expect(entity.venueName == "Cat's Cradle")
    }

    @Test("prefers the concert's own title over the billed headliner when both are present")
    func headlinerPrefersConcertTitle() throws {
        let concert = Concert.stub(headliningArtistRaw: "Jessica Pratt", title: "Cat's Cradle Presents")
        let entity = try #require(ConcertEntity(concert: concert))

        #expect(entity.headlinerName == "Cat's Cradle Presents")
    }

    @Test("carries the source concert's starts-on date")
    func carriesStartsOn() throws {
        let concert = Concert.stub(startsOn: Concert.defaultStartsOn)
        let entity = try #require(ConcertEntity(concert: concert))

        #expect(entity.startsOn == Concert.defaultStartsOn)
    }

    @Test("composes the subtitle as venue — city, state")
    func subtitleComposesVenueLocation() throws {
        let concert = Concert.stub(venue: .stub(name: "Cat's Cradle", city: "Carrboro", state: "NC"))
        let entity = try #require(ConcertEntity(concert: concert))

        #expect(entity.subtitleText == "Cat's Cradle — Carrboro, NC")
    }

    @Test("uses the headliner name as the display representation title")
    func displayRepresentationUsesHeadlinerName() throws {
        let concert = Concert.stub(headliningArtistRaw: "Chuquimamani-Condori")
        let entity = try #require(ConcertEntity(concert: concert))

        let representation = entity.displayRepresentation
        let titleString = String(localized: representation.title)

        #expect(titleString == "Chuquimamani-Condori")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("populates the CoreSpotlight attribute set with Spotlight-visible metadata")
    func attributeSetCarriesSpotlightFields() throws {
        let concert = Concert.stub(
            id: 4821,
            venue: .stub(name: "Cat's Cradle", city: "Carrboro", state: "NC"),
            startsOn: Concert.defaultStartsOn,
            headliningArtistRaw: "Jessica Pratt"
        )
        let entity = try #require(ConcertEntity(concert: concert))

        let set = entity.attributeSet

        #expect(set.title == "Jessica Pratt")
        #expect(set.contentDescription == entity.subtitleText)
        #expect(set.contentCreationDate == Concert.defaultStartsOn)
        #expect(set.relatedUniqueIdentifier == "4821")
    }
    #endif
}
