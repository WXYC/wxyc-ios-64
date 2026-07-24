//
//  ConcertEntityQuery.swift
//  Intents
//
//  AppEntity query for ConcertEntity, mirroring `PlaycutEntityQuery`/
//  `ShowEntityQuery`. Lands a wireable shape with an injectable source and a
//  safe empty default; the production `entities(for:)` source binding is a
//  later slice. F3 wires the iOS 27-gated `IndexedEntityQuery` reindex
//  handlers (`ConcertEntityQuery+IndexedEntityQuery.swift`), which read the
//  `reindexer`/`concertsFetching`/`analytics` `@Dependency` properties below.
//
//  All three `@Dependency`-backed properties are declared here — not in the
//  F3 extension file — because a Swift extension cannot add stored
//  properties, and `@Dependency`'s backing storage is a stored property.
//  They're unused outside the iOS 27 reindex extension but must live on the
//  primary struct declaration for that extension to reach them, mirroring
//  `PlaycutEntityQuery`'s `reindexer`/`analytics` properties exactly.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import Concerts
import Foundation

public struct ConcertEntityQuery: EntityQuery {
    public typealias ConcertSource = @Sendable ([Int]) async -> [Concert]

    /// Donation seam the F3 reindex handlers use to re-donate entities to
    /// Spotlight. See the stored-property-in-an-extension rationale above.
    @Dependency
    var reindexer: any ConcertReindexer

    /// Fetch seam the F3 reindex handlers use to resolve concerts by id
    /// (`reindexEntities(for:)`) and to fetch the curated window
    /// (`reindexAllEntities()`). Distinct from `source` below: `source` is
    /// this query's own `entities(for:)` seam (injectable via `init(source:)`
    /// for tests, empty by default in production); the reindex handlers need
    /// a real network-capable fetcher, injected the same way
    /// `PlaycutEntityQuery.historyStore` is — there's no app-level call site
    /// between the system and an `IndexedEntityQuery` handler through which
    /// to pass one as a parameter, unlike `ToursNearMe.perform()` (app
    /// target), which builds its own via `AppIntentServices.concertsFetcher()`.
    @Dependency
    var concertsFetching: any ConcertsFetching

    /// Analytics seam the F3 reindex handlers use to report
    /// `SpotlightReindexRequested` (#445). See the stored-property-in-an-
    /// extension rationale above.
    @Dependency
    var analytics: any AnalyticsService

    /// Injectable seam for `entities(for:)`. Production `init()` (the
    /// AppIntents runtime's entry point) defaults it to an empty source — the
    /// safe F1 default this type shipped with; the F3 reindex handlers below
    /// resolve through `concertsFetching` instead, not through this closure.
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
