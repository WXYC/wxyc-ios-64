//
//  StationEntity.swift
//  Intents
//
//  A singleton `AppEntity` for WXYC itself — CC-C2. Nothing in the codebase
//  before this made "WXYC" an addressable proper noun: no entity a Maps
//  destination or a "share WXYC's stream" cross-app context could anchor to.
//  `UniqueAppEntity` (iOS 18+) is Apple's purpose-built shape for exactly
//  this — one entity, `id` fixed at construction instead of derived, no
//  disambiguation `EntityQuery` to write, so identifier collision is
//  impossible by construction. Deliberately distinct from
//  `LiveRadioStationEntity` (the iOS-27 `.audio.liveRadioStation` schema
//  entity that routes "Hey Siri, play WXYC" voice playback, #494): that one
//  is playback-shaped and gated behind the audio AppSchema; this one is a
//  place, independent of any playback state, and works down to this
//  package's iOS 18.4 floor.
//
//  `placeDescriptor` bridges to `PlaceDescriptor` (CC-C2's
//  `IntentValueRepresentation` target) with the WXYC studio's coordinates —
//  the Frank Porter Graham Student Union (Carolina Union), 209 South Rd,
//  Chapel Hill, NC 27514, on UNC's campus. Deliberately the studio, not the
//  transmitter: WXYC's transmitter sits on Jones Ferry Road in Chatham
//  County, well off campus — geocoding that would make "WXYC studios"
//  resolve to the wrong building entirely. Coordinates geocoded via
//  OpenStreetMap Nominatim, matched as a named point of interest — same
//  method `VenueCoordinate.swift` (Concerts package) uses for concert venues.
//
//  `PlaceDescriptor` itself ships at iOS 26.0 and is present in the stable
//  Xcode 26.5 SDK, so `placeDescriptor` only needs an
//  `@available(iOS 26.0, *)`-shaped gate. The `Transferable`/
//  `IntentValueRepresentation` wiring below it needs more:
//  `IntentValueRepresentation` carries an `@available(iOS 26.4, *)`
//  annotation but does not exist at all in the stable SDK — only the Xcode 27
//  beta toolchain's iOS 27.0 SDK declares it — so that part is
//  `#if compiler(>=6.4)`-gated, same shape as `LiveRadioStationEntity`'s iOS
//  27 gate and `DJEntity`'s CC-C1 bridge.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import GeoToolbox

public struct StationEntity: AppEntity, UniqueAppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Station")

    public static let defaultQuery = UniqueAppEntityProvider { StationEntity() }

    /// Fixed at construction, not derived from anything — the property that
    /// makes identifier collision impossible by construction (a singleton
    /// has nothing else to collide with).
    public let id = "wxyc"

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "WXYC 89.3 FM")
    }

    public init() {}
}

@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, *)
extension StationEntity {
    /// WXYC's studio (see the file header for the address and why it's the
    /// studio and not the transmitter).
    public var placeDescriptor: PlaceDescriptor {
        PlaceDescriptor(
            representations: [
                .coordinate(CLLocationCoordinate2D(latitude: 35.9103868, longitude: -79.0474769))
            ],
            commonName: "WXYC 89.3 FM"
        )
    }

    /// The inverse of `placeDescriptor`. `StationEntity` is a singleton, so
    /// every `PlaceDescriptor` — including ones this bridge didn't
    /// produce — resolves back to the one station; there's no field that can
    /// fail to parse.
    public static func from(placeDescriptor: PlaceDescriptor) -> StationEntity {
        StationEntity()
    }
}

#if compiler(>=6.4)
import CoreTransferable

@available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, *)
extension StationEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        IntentValueRepresentation(
            exporting: { station in station.placeDescriptor },
            importing: { place in StationEntity.from(placeDescriptor: place) }
        )
    }
}
#endif
