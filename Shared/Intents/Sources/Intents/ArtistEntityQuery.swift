//
//  ArtistEntityQuery.swift
//  Intents
//
//  AppEntity query for ArtistEntity. F5b lands a minimal, wireable shape: the
//  injected source hands back the playcut cache, and `entities(for:)` derives
//  one deduped ArtistEntity per normalized artist name and resolves the
//  requested identifiers against that set. Donation and a richer per-artist
//  query (search-by-name, suggestions) land in C6.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Playlist

public struct ArtistEntityQuery: EntityQuery {
    public typealias PlaycutSource = @Sendable () async -> [Playcut]

    private let source: PlaycutSource

    public init() {
        self.init(source: { [] })
    }

    public init(source: @escaping PlaycutSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities by deduping the source's playcuts
    /// down to one ArtistEntity per normalized artist name, then looking up
    /// each requested id. Preserves the input order and drops ids the source
    /// couldn't resolve, matching the AppIntents `entities(for:)` contract.
    public func entities(for identifiers: [ArtistID]) async throws -> [ArtistEntity] {
        let playcuts = await source()
        let entitiesByID = Dictionary(
            playcuts.map { ArtistEntity(artistName: $0.artistName) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return identifiers.compactMap { entitiesByID[$0] }
    }

    public func suggestedEntities() async throws -> [ArtistEntity] {
        []
    }
}
