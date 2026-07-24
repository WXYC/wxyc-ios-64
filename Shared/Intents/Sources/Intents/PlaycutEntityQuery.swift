//
//  PlaycutEntityQuery.swift
//  Intents
//
//  AppEntity query for PlaycutEntity. F1 landed a wireable shape with an
//  injectable source and safe empty defaults. F3 wires the production path:
//  the no-arg `init()` the AppIntents runtime uses resolves playcuts through
//  a `PlaycutHistoryStore` requested via `@Dependency` instead of returning
//  an empty stub, and (in the iOS 27-gated
//  `PlaycutEntityQuery+IndexedEntityQuery.swift`) the query adopts
//  `IndexedEntityQuery` to participate in Spotlight's reindex recovery loop.
//
//  Both `@Dependency`-backed properties are declared here — not in the F3
//  extension file — because a Swift extension cannot add stored properties,
//  and `@Dependency`'s backing storage is a stored property. `reindexer` is
//  unused outside the iOS 27 extension but must live on the primary struct
//  declaration for that extension to reach it. `analytics` (#445) is the
//  same story: only the iOS 27 reindex extension reads it, to report
//  `SpotlightReindexRequested`.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import Foundation
import Playlist

public struct PlaycutEntityQuery: EntityQuery {
    public typealias PlaycutSource = @Sendable ([Playcut.ID]) async -> [Playcut]

    /// Production playcut source. Resolved lazily by the AppIntents runtime
    /// the first time it's read, so unit tests that go through
    /// `init(source:)` never touch it (and never trip its
    /// registered-or-trap contract). Registered in `Singletonia.init()`
    /// before any intent/query can run — see `WXYC/iOS/Singletonia.swift`.
    @Dependency
    var historyStore: PlaycutHistoryStore

    /// Donation seam the F3 reindex handlers use to re-donate entities to
    /// Spotlight. Declared here (not in the reindex extension) for the same
    /// stored-property-in-an-extension reason as `historyStore`; unused by
    /// this file's own `entities(for:)`/`suggestedEntities()`.
    @Dependency
    var reindexer: any PlaycutReindexer

    /// Analytics seam the F3 reindex handlers use to report
    /// `SpotlightReindexRequested` (#445). Declared here for the same
    /// stored-property-in-an-extension reason as `historyStore`/`reindexer`;
    /// unused by this file's own `entities(for:)`/`suggestedEntities()`.
    @Dependency
    var analytics: any AnalyticsService

    /// Injectable seam for tests. `nil` in production, where `init()` (the
    /// AppIntents runtime's entry point) leaves it unset and `entities(for:)`
    /// falls back to `historyStore`.
    private let source: PlaycutSource?

    public init() {
        self.source = nil
    }

    public init(source: @escaping PlaycutSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities via the injected source (tests) or
    /// `historyStore` (production). The result preserves the input order and
    /// drops ids that couldn't be resolved, matching the AppIntents
    /// `entities(for:)` contract. Duplicate ids in the resolved set collapse
    /// to the first occurrence — the query never traps.
    public func entities(for identifiers: [PlaycutID]) async throws -> [PlaycutEntity] {
        let rawIDs = identifiers.map(\.value)
        let playcuts = await resolvePlaycuts(for: rawIDs)
        let byID = Dictionary(
            playcuts.map { ($0.id, PlaycutEntity(playcut: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        return rawIDs.compactMap { byID[$0] }
    }

    public func suggestedEntities() async throws -> [PlaycutEntity] {
        []
    }

    private func resolvePlaycuts(for ids: [UInt64]) async -> [Playcut] {
        if let source {
            return await source(ids)
        }
        return await historyStore.playcuts(ids: Set(ids))
    }
}
