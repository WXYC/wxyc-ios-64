//
//  StationEntityTests.swift
//  WXYCIntents
//
//  Field-mapping coverage for CC-C2 — the `StationEntity` singleton and its
//  `PlaceDescriptor` bridge. Pins the fixed id/title, the coordinate/common
//  name the bridge produces, and that importing back preserves the
//  singleton's identity (there's no other identity a `PlaceDescriptor` could
//  produce). `placeDescriptor` only needs iOS/macOS/watchOS/tvOS 26.0
//  (`PlaceDescriptor` is present in the stable SDK), so those tests run
//  whenever the test host is macOS 26+; the `Transferable`/
//  `IntentValueRepresentation` wiring in `StationEntity.swift` needs Swift
//  6.4 (see that file's header) so it isn't exercised here — these tests
//  cover the pure `placeDescriptor`/`from(placeDescriptor:)` conversion the
//  gated conformance delegates to.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import GeoToolbox
import Testing
@testable import WXYCIntents

@Suite("StationEntity (CC-C2)")
struct StationEntityTests {
    @Test("the station has a stable id and title")
    func stationIdentity() {
        let station = StationEntity()

        #expect(station.id == "wxyc")
        #expect(String(localized: station.displayRepresentation.title) == "WXYC 89.3 FM")
    }

    @Test("two independent constructions carry the same singleton id")
    func stationIsASingleton() {
        #expect(StationEntity().id == StationEntity().id)
    }

    @Test("the default query resolves the one station")
    func defaultQueryResolvesTheStation() async throws {
        let station = try await StationEntity.defaultQuery.uniqueEntity()

        #expect(station.id == "wxyc")
    }

    @Test("placeDescriptor carries the studio coordinate and common name")
    func placeDescriptorMapsFields() {
        guard #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *) else { return }

        let place = StationEntity().placeDescriptor

        #expect(place.commonName == "WXYC 89.3 FM")
        #expect(
            place.representations == [
                .coordinate(CLLocationCoordinate2D(latitude: 35.9103868, longitude: -79.0474769))
            ]
        )
        #expect(place.supportingRepresentations.isEmpty)
    }

    @Test("importing any PlaceDescriptor resolves back to the one station")
    func importingPreservesIdentity() {
        guard #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *) else { return }

        let roundTripped = StationEntity.from(placeDescriptor: StationEntity().placeDescriptor)
        let unrelated = StationEntity.from(
            placeDescriptor: PlaceDescriptor(representations: [.address("nowhere")], commonName: nil)
        )

        #expect(roundTripped.id == "wxyc")
        #expect(unrelated.id == "wxyc")
    }
}
