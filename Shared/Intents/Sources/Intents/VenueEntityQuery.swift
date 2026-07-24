//
//  VenueEntityQuery.swift
//  Intents
//
//  AppEntity query for VenueEntity, mirroring `ConcertEntityQuery`. Lands a
//  wireable shape with an injectable source and a safe empty default; the
//  production `entities(for:)` source binding, the distinct-venues
//  `suggestedEntities()`, and the donation pipeline are later slices
//  (declaration only per OT-F4 — see `docs/ideas/spotlight-on-tour-entities.md`).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Concerts
import Foundation

public struct VenueEntityQuery: EntityQuery {
    public typealias VenueSource = @Sendable ([Int]) async -> [Venue]

    /// Injectable seam for `entities(for:)`. Production `init()` (the
    /// AppIntents runtime's entry point) defaults it to an empty source — the
    /// safe F4 default this type ships with.
    private let source: VenueSource

    public init() {
        self.init(source: { _ in [] })
    }

    public init(source: @escaping VenueSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities via the injected source.
    /// `identifiers` bridges to the backend's `Int` id space first (see
    /// `EntityID.venueID`), dropping any entry that doesn't fit — defensive,
    /// never the case for an id this app itself constructed. The result
    /// preserves the input order and drops ids the source couldn't resolve,
    /// matching the AppIntents `entities(for:)` contract. If the source
    /// returns duplicate ids the first one wins — the query never traps.
    public func entities(for identifiers: [VenueID]) async throws -> [VenueEntity] {
        let rawIDs = identifiers.compactMap(\.venueID)
        let venues = await source(rawIDs)
        let byID = Dictionary(
            venues.compactMap { venue in VenueEntity(venue: venue).map { (venue.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        return rawIDs.compactMap { byID[$0] }
    }

    public func suggestedEntities() async throws -> [VenueEntity] {
        []
    }
}
