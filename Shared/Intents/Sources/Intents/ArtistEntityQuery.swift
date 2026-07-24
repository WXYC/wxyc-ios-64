//
//  ArtistEntityQuery.swift
//  Intents
//
//  AppEntity query for ArtistEntity. F5b landed a minimal, wireable shape:
//  the injected source hands back the playcut cache, and `entities(for:)`
//  derives one deduped ArtistEntity per normalized artist name and resolves
//  the requested identifiers against that set. C6 adds two things on top of
//  that same dedup grouping: each resolved entity now carries its
//  `playCount` (the size of its dedup group), and `playcuts(forArtist:)`
//  answers the richer "all playcuts where normalized artistName ==
//  self.key" query the donation pipeline and any future UI need.
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
    /// down to one ArtistEntity per normalized artist name — each carrying
    /// the play count of its dedup group — then looking up each requested
    /// id. Preserves the input order and drops ids the source couldn't
    /// resolve, matching the AppIntents `entities(for:)` contract.
    public func entities(for identifiers: [ArtistID]) async throws -> [ArtistEntity] {
        let playcuts = await source()
        let entitiesByID = Dictionary(
            uniqueKeysWithValues: Self.groupedByNormalizedArtist(playcuts).map { normalized, group in
                (ArtistID(stableEntityID(for: normalized)), ArtistEntity(artistName: normalized, playCount: group.count))
            }
        )
        return identifiers.compactMap { entitiesByID[$0] }
    }

    public func suggestedEntities() async throws -> [ArtistEntity] {
        []
    }

    /// All playcuts from the source whose normalized artist name matches
    /// `id` — the "all playcuts by this artist" query C6 adds. Backs a
    /// future "show me what WXYC has played by Stereolab" surface: passing
    /// `ArtistEntity(artistName: "Stereolab").id` returns every playcut
    /// whose artist name normalizes the same way, including "feat. …"
    /// variants and casing/whitespace differences.
    public func playcuts(forArtist id: ArtistID) async throws -> [Playcut] {
        let playcuts = await source()
        return playcuts.filter { ArtistID(stableEntityID(for: normalizedEntityKey($0.artistName))) == id }
    }

    /// Groups `playcuts` by normalized artist name, using the normalized
    /// name itself (not the first-seen raw name) as the dictionary key so
    /// callers get a stable, already-normalized string back.
    private static func groupedByNormalizedArtist(_ playcuts: [Playcut]) -> [String: [Playcut]] {
        Dictionary(grouping: playcuts) { normalizedEntityKey($0.artistName) }
    }
}
