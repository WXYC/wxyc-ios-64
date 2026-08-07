//
//  BackendKeyedEntityConformanceTests.swift
//  WXYCIntents
//
//  Replacement for ShowEntityTests and VenueEntityTests (#760). Unlike the
//  normalized-string-keyed entities (see NormalizedKeyEntityConformanceTests.swift),
//  ShowEntity and VenueEntity key on a backend row id, so the shared contract
//  worth parameterizing is narrower — mirroring the source's id, rendering
//  the expected display title, and tying the attribute set back to that id.
//  Each carries genuinely different extra fields on top (Show's optional
//  message subtitle; Venue's city/state and bundled geo lookup, plus the
//  failable id-bridging initializer), which stay as dedicated tests below
//  rather than forcing them into an artificial shared shape.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Concerts
import ConcertsTesting
import Playlist
import PlaylistTesting
@testable import WXYCIntents
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

@Suite("Backend-keyed entity conformance")
struct BackendKeyedEntityConformanceTests {
    @Test("mirrors the source's backend id", arguments: backendKeyedEntityCases)
    func mirrorsSourceID(_ testCase: BackendKeyedEntityCase) {
        #expect(testCase.entityIdentifierString() == testCase.expectedEntityIdentifierString)
    }

    @Test("displayRepresentation renders the expected title", arguments: backendKeyedEntityCases)
    func displayRepresentationRendersExpectedTitle(_ testCase: BackendKeyedEntityCase) {
        #expect(testCase.displayTitle() == testCase.expectedDisplayTitle)
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("attribute set carries the expected title and ties back to the entity id", arguments: backendKeyedEntityCases)
    func attributeSetCarriesExpectedFields(_ testCase: BackendKeyedEntityCase) {
        let fields = testCase.attributeSetFields()

        #expect(fields.title == testCase.expectedDisplayTitle)
        #expect(fields.relatedUniqueIdentifier == testCase.expectedEntityIdentifierString)
    }
    #endif
}

// MARK: - ShowEntity extras: the optional message subtitle

@Suite("ShowEntity extras")
struct ShowEntityExtraTests {
    @Test("falls back to the station name when the show marker has no DJ name")
    func displayTitleFallsBackToStationName() {
        let signOn = ShowMarker.stub(djName: nil)
        let entity = ShowEntity(start: signOn)

        let titleString = String(localized: entity.displayRepresentation.title)

        #expect(titleString == "WXYC")
    }

    @Test("carries a nil subtitle when the show marker has an empty message")
    func subtitleNilForEmptyMessage() {
        let signOn = ShowMarker.stub(djName: "Jake B", message: "")
        let entity = ShowEntity(start: signOn)

        #expect(entity.subtitleText == nil)
    }

    @Test("carries the show marker's message as the subtitle")
    func subtitleUsesMessage() {
        let signOn = ShowMarker.stub(djName: "Jake B", message: "freeform on a Tuesday")
        let entity = ShowEntity(start: signOn)

        #expect(entity.subtitleText == "freeform on a Tuesday")
    }
}

// MARK: - VenueEntity extras: failable id bridging, city/state, bundled geo

@Suite("VenueEntity extras")
struct VenueEntityExtraTests {
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

    @Test("composes the subtitle as city, state")
    func subtitleComposesCityState() throws {
        let venue = Venue.stub(city: "Carrboro", state: "NC")
        let entity = try #require(VenueEntity(venue: venue))

        #expect(entity.subtitleText == "Carrboro, NC")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("sets geo fields on the attribute set when the venue's slug is in the bundled coordinate table (OT-C4)")
    func attributeSetSetsGeoForKnownSlug() throws {
        let venue = Venue.stub(slug: "cats-cradle", name: "Cat's Cradle")
        let entity = try #require(VenueEntity(venue: venue))
        let coordinate = try #require(VenueCoordinates.coordinate(forSlug: "cats-cradle"))

        let set = entity.attributeSet

        #expect(set.latitude?.doubleValue == coordinate.latitude)
        #expect(set.longitude?.doubleValue == coordinate.longitude)
        #expect(set.supportsNavigation?.boolValue == true)
        #expect(set.namedLocation == "Cat's Cradle")
    }

    @Test("leaves geo fields unset — no crash — for a venue whose slug isn't in the bundled table (OT-C4)")
    func attributeSetOmitsGeoForUnknownSlug() throws {
        let venue = Venue.stub(slug: "some-brand-new-venue-not-yet-added", name: "Some New Venue")
        let entity = try #require(VenueEntity(venue: venue))

        let set = entity.attributeSet

        #expect(set.latitude == nil)
        #expect(set.longitude == nil)
        #expect(set.supportsNavigation == nil)
        #expect(set.namedLocation == nil)
        // Still a searchable name, even without geo — the graceful path.
        #expect(set.title == "Some New Venue")
    }
    #endif
}

// MARK: - Mocks and descriptors

/// One backend-id-keyed `AppEntity` type under test — `ShowEntity`,
/// `VenueEntity` today. Each case builds one representative entity and
/// exposes its id/title/attribute-set fields as closures, so the shared
/// mirrors-id/display-title/attribute-set assertions above don't need to
/// know the concrete `AppEntity`/`ID`/source-model type.
struct BackendKeyedEntityCase: Sendable {
    let typeName: String
    let expectedEntityIdentifierString: String
    let expectedDisplayTitle: String
    let entityIdentifierString: @Sendable () -> String
    let displayTitle: @Sendable () -> String
    /// Reads the entity's Spotlight attribute set. Declared unconditionally,
    /// with the platform condition inside each closure body instead — Swift
    /// has no `#if` inside an argument list, so gating the property here would
    /// leave the `attributeSetFields:` arguments below unconditional and break
    /// the watch/tv build. See `NormalizedKeyEntityCase` for the same note.
    let attributeSetFields: @Sendable () -> (title: String?, relatedUniqueIdentifier: String?)
}

let backendKeyedEntityCases: [BackendKeyedEntityCase] = [
    BackendKeyedEntityCase(
        typeName: "ShowEntity",
        expectedEntityIdentifierString: "99",
        expectedDisplayTitle: "Jake B",
        entityIdentifierString: {
            ShowEntity(start: .stub(id: 99, djName: "Jake B")).id.entityIdentifierString
        },
        displayTitle: {
            String(localized: ShowEntity(start: .stub(id: 99, djName: "Jake B")).displayRepresentation.title)
        },
        attributeSetFields: {
            #if !os(watchOS) && !os(tvOS)
            let set = ShowEntity(start: .stub(id: 99, djName: "Jake B")).attributeSet
            return (set.title, set.relatedUniqueIdentifier)
            #else
            return (nil, nil)
            #endif
        }
    ),
    BackendKeyedEntityCase(
        typeName: "VenueEntity",
        expectedEntityIdentifierString: "3",
        expectedDisplayTitle: "Cat's Cradle",
        entityIdentifierString: {
            VenueEntity(venue: .stub(id: 3, name: "Cat's Cradle"))?.id.entityIdentifierString ?? ""
        },
        displayTitle: {
            VenueEntity(venue: .stub(id: 3, name: "Cat's Cradle")).map {
                String(localized: $0.displayRepresentation.title)
            } ?? ""
        },
        attributeSetFields: {
            #if !os(watchOS) && !os(tvOS)
            guard let set = VenueEntity(venue: .stub(id: 3, name: "Cat's Cradle"))?.attributeSet else {
                return (nil, nil)
            }
            return (set.title, set.relatedUniqueIdentifier)
            #else
            return (nil, nil)
            #endif
        }
    ),
]
