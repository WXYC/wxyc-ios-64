//
//  VenueEntity.swift
//  Intents
//
//  App Intents bridge from a domain-model Venue (a live-music venue embedded
//  in a Concert) to a Spotlight-indexable AppEntity, mirroring `ConcertEntity`.
//  Carries just enough to present a minimal Siri/Spotlight result — venue
//  name as title, city/state as subtitle — for a single venue.
//
//  OT-F4 shipped the declaration; OT-C4 adds the bundled-table geo affordances
//  below (no donation pipeline yet). Sibling of the parent epic's F5 entity
//  declarations. See `docs/ideas/spotlight-on-tour-entities.md`.
//
//  `EntityID`'s storage is `UInt64`, but the backend's `Venue.id` (embedded on
//  `Concert.venue`) speaks `Int`. The two representations coexist via the
//  bridging initializer/property below, the same choice OT-F1 made for
//  `ConcertID`, rather than generalizing `EntityID` over its raw type.
//
//  The `IndexedEntity` conformance and the `CoreSpotlight`-backed
//  `attributeSet` are gated to platforms where CoreSpotlight exists, exactly
//  like `ConcertEntity`'s gate.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Concerts
import Foundation
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

public typealias VenueID = EntityID<VenueEntity>

extension EntityID where Owner == VenueEntity {
    /// Bridges a backend venue id (`Venue.id`) into the Spotlight identity
    /// space. `nil` for a negative id — defensive; backend venue ids are
    /// positive serials, but `EntityID`'s storage is `UInt64` and
    /// `UInt64(negative)` traps, so the guard must run before the conversion.
    public init?(venueID: Int) {
        guard venueID >= 0 else { return nil }
        self.init(UInt64(venueID))
    }

    /// Bridges back to the backend's `Int` id space that `Venue.id` speaks.
    /// `nil` when the stored value doesn't fit `Int` — the defensive
    /// counterpart to the guard above; every `VenueID` this app constructs
    /// already satisfies it by construction.
    public var venueID: Int? {
        Int(exactly: value)
    }
}

public struct VenueEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Venue",
        numericFormat: "\(placeholder: .int) venues"
    )

    public static let defaultQuery = VenueEntityQuery()

    public var id: VenueID

    /// Composed "City, State" so the subtitle string and Spotlight's
    /// `contentDescription` share it without re-formatting.
    public let subtitleText: String

    /// The backend's stable venue key (`Venue.slug`) — not shown to the
    /// user, only used to look up bundled geo coordinates (OT-C4, see
    /// `VenueCoordinates`).
    let slug: String

    @Property(title: "Name")
    public var name: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitleText)"
        )
    }

    /// Builds the entity from a domain-model `Venue`. Fails only when
    /// `venue.id` is negative (see `EntityID.init?(venueID:)`) — never the
    /// case for a real backend row, but the guard keeps this initializer
    /// crash-free rather than force-unwrapping the id bridge.
    public init?(venue: Venue) {
        guard let id = VenueID(venueID: venue.id) else { return nil }
        self.id = id
        self.subtitleText = "\(venue.city), \(venue.state)"
        self.slug = venue.slug
        self.name = venue.name
    }
}

#if !os(watchOS) && !os(tvOS)
extension VenueEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.title = name
        set.contentDescription = subtitleText
        // Ties the CoreSpotlight item back to the AppEntity so a Spotlight
        // tap resolves to this specific venue.
        set.relatedUniqueIdentifier = id.entityIdentifierString
        // Bundled slug -> coordinate lookup (OT-C4). A venue outside the
        // table indexes as a searchable name with no geo — the documented,
        // graceful miss path (`VenueCoordinates.coordinate(forSlug:)`), not
        // an error.
        if let coordinate = VenueCoordinates.coordinate(forSlug: slug) {
            set.latitude = NSNumber(value: coordinate.latitude)
            set.longitude = NSNumber(value: coordinate.longitude)
            set.supportsNavigation = true
            set.namedLocation = name
        }
        return set
    }
}
#endif
