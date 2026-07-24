//
//  ConcertEntity.swift
//  Intents
//
//  App Intents bridge from a domain-model Concert (an On Tour touring show)
//  to a Spotlight-indexable AppEntity, mirroring `PlaycutEntity`/`ShowEntity`.
//  Carries just enough to present a minimal Siri/Spotlight result — headliner
//  as title, venue/city/state as subtitle — for a single concert.
//
//  Distinct from `ShowEntity`/`wxyc.shows` (a radio DJ airing): On Tour
//  speaks "show" everywhere on the wire (`/shows/<id>`, `ShowStatus`), but
//  this entity models a touring concert, so it stays `ConcertEntity` /
//  `wxyc.concerts` rather than aligning to `Show*` naming. See
//  `docs/ideas/spotlight-on-tour-entities.md`.
//
//  `EntityID`'s storage is `UInt64`, but the backend's `Concert.id` (and
//  `WXYCDeepLink.concert`, `Concert.shareURL`) speak `Int`. The two
//  representations coexist via the bridging initializer/property below
//  rather than generalizing `EntityID` over its raw type or retyping the
//  shipped deep link — see the design doc's identifier-strategy section.
//
//  The `IndexedEntity` conformance and the `CoreSpotlight`-backed
//  `attributeSet` are gated to platforms where CoreSpotlight exists, exactly
//  like `PlaycutEntity`'s gate. The attribute set's `thumbnailURL` mirrors
//  `PlaycutEntity.artworkURL`'s pattern, surfacing `Concert.imageURL`
//  directly (no async fetch). Donation (populating the `wxyc.concerts`
//  index) and further attributes (geo, genre keywords) are later slices
//  (OT-F2/OT-F3, OT-C4) — this type only makes a concert addressable as an
//  entity.
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

public typealias ConcertID = EntityID<ConcertEntity>

extension EntityID where Owner == ConcertEntity {
    /// Bridges a backend concert id (`Concert.id`) into the Spotlight
    /// identity space. `nil` for a negative id — defensive; backend concert
    /// ids are positive serials, but `EntityID`'s storage is `UInt64` and
    /// `UInt64(negative)` traps, so the guard must run before the conversion.
    public init?(concertID: Int) {
        guard concertID >= 0 else { return nil }
        self.init(UInt64(concertID))
    }

    /// Bridges back to the backend's `Int` id space that `Concert.id`,
    /// `WXYCDeepLink.concert`, and `Concert.shareURL` speak. `nil` when the
    /// stored value doesn't fit `Int` — the defensive counterpart to the
    /// guard above; every `ConcertID` this app constructs already satisfies
    /// it by construction.
    public var concertID: Int? {
        Int(exactly: value)
    }
}

public struct ConcertEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Concert",
        numericFormat: "\(placeholder: .int) concerts"
    )

    public static let defaultQuery = ConcertEntityQuery()

    public var id: ConcertID

    /// The venue-local calendar day of the show. Not a `@Property` — mirrors
    /// `PlaycutEntity.broadcastDate`, supporting data for the attribute set
    /// rather than a Siri-facing search parameter.
    public let startsOn: Date

    /// Composed "Venue — City, State" so the subtitle string and Spotlight's
    /// `contentDescription` share it without re-formatting.
    public let subtitleText: String

    /// Event/promo poster image — surfaced as the Spotlight thumbnail so
    /// results carry poster art rather than a placeholder glyph, mirroring
    /// `PlaycutEntity.artworkURL`.
    public let imageURL: URL?

    @Property(title: "Headliner")
    public var headlinerName: String

    @Property(title: "Venue")
    public var venueName: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(headlinerName)",
            subtitle: "\(subtitleText)"
        )
    }

    /// Builds the entity from a domain-model `Concert`. Fails only when
    /// `concert.id` is negative (see `EntityID.init?(concertID:)`) — never
    /// the case for a real backend row, but the guard keeps this initializer
    /// crash-free rather than force-unwrapping the id bridge.
    public init?(concert: Concert) {
        guard let id = ConcertID(concertID: concert.id) else { return nil }
        self.id = id
        self.startsOn = concert.startsOn
        self.subtitleText = "\(concert.venue.name) — \(concert.venue.city), \(concert.venue.state)"
        self.imageURL = concert.imageURL
        self.headlinerName = concert.headlineName
        self.venueName = concert.venue.name
    }
}

#if !os(watchOS) && !os(tvOS)
extension ConcertEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.title = headlinerName
        set.contentDescription = subtitleText
        set.contentCreationDate = startsOn
        set.thumbnailURL = imageURL
        // Ties the CoreSpotlight item back to the AppEntity so a Spotlight tap
        // resolves to this specific concert via OpenConcert.
        set.relatedUniqueIdentifier = id.entityIdentifierString
        return set
    }
}
#endif
