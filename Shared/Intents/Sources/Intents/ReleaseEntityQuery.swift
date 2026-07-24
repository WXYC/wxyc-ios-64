//
//  ReleaseEntityQuery.swift
//  Intents
//
//  AppEntity query for ReleaseEntity. Mirrors ArtistEntityQuery's minimal
//  shape: the injected source hands back the playcut cache, and
//  `entities(for:)` derives one deduped ReleaseEntity per normalized
//  (artist, release) composite and resolves the requested identifiers
//  against that set. Donation and a richer per-release query (search-by-title,
//  suggestions) are deferred, matching ArtistEntityQuery.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Playlist

public struct ReleaseEntityQuery: EntityQuery {
    public typealias PlaycutSource = @Sendable () async -> [Playcut]

    private let source: PlaycutSource

    public init() {
        self.init(source: { [] })
    }

    public init(source: @escaping PlaycutSource) {
        self.source = source
    }

    /// Resolves `identifiers` to entities by deduping the source's playcuts
    /// down to one ReleaseEntity per normalized (artist, release) composite,
    /// then looking up each requested id. Playcuts with no release title are
    /// skipped — there is nothing to key a release entity on. Preserves the
    /// input order and drops ids the source couldn't resolve, matching the
    /// AppIntents `entities(for:)` contract.
    public func entities(for identifiers: [ReleaseID]) async throws -> [ReleaseEntity] {
        let playcuts = await source()
        let entitiesByID = Dictionary(
            playcuts.compactMap { playcut -> ReleaseEntity? in
                guard let releaseTitle = playcut.releaseTitle, !releaseTitle.isEmpty else { return nil }
                return ReleaseEntity(artistName: playcut.artistName, releaseTitle: releaseTitle)
            }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return identifiers.compactMap { entitiesByID[$0] }
    }

    public func suggestedEntities() async throws -> [ReleaseEntity] {
        []
    }
}
