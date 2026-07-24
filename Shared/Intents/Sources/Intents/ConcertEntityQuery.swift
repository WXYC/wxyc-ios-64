//
//  ConcertEntityQuery.swift
//  Intents
//
//  AppEntity query for ConcertEntity, mirroring `PlaycutEntityQuery`/
//  `ShowEntityQuery`. Lands a wireable shape with an injectable source and a
//  safe empty default; the production source binding, reindex handlers, and
//  `IndexedEntityQuery` conformance are a later slice (OT-F3).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Concerts
import Foundation

public struct ConcertEntityQuery: EntityQuery {
    public typealias ConcertSource = @Sendable ([Int]) async -> [Concert]

    private let source: ConcertSource

    public init() {
        self.init(source: { _ in [] })
    }

    public init(source: @escaping ConcertSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities via the injected source. `identifiers`
    /// bridges to the backend's `Int` id space first (see `EntityID.concertID`),
    /// dropping any entry that doesn't fit — defensive, never the case for an
    /// id this app itself constructed. The result preserves the input order and
    /// drops ids the source couldn't resolve, matching the AppIntents
    /// `entities(for:)` contract. If the source returns duplicate ids the first
    /// one wins — the query never traps.
    public func entities(for identifiers: [ConcertID]) async throws -> [ConcertEntity] {
        let rawIDs = identifiers.compactMap(\.concertID)
        let concerts = await source(rawIDs)
        let byID = Dictionary(
            concerts.compactMap { concert in ConcertEntity(concert: concert).map { (concert.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        return rawIDs.compactMap { byID[$0] }
    }

    public func suggestedEntities() async throws -> [ConcertEntity] {
        []
    }
}
