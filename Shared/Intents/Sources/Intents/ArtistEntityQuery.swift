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
//  OT-C6 (WXYC/wxyc-ios-64#629) adds `concerts(forArtist:)`, the cross-link
//  from the playlist graph into On Tour: an artist's upcoming curated
//  concerts, resolved by intersecting the WXYC catalog artist ids of the
//  artist's own playcuts (`Playcut.artistId`) against `Concert.headliningArtistId`
//  — the same keyspace `ForYouShelf`'s loved tier joins on. Never falls back to
//  name matching: an artist whose plays never resolved a catalog id has
//  nothing to intersect on and returns `[]`.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Concerts
import Foundation
import Playlist

public struct ArtistEntityQuery: EntityQuery {
    public typealias PlaycutSource = @Sendable () async -> [Playcut]
    public typealias ConcertSource = @Sendable () async -> [Concert]

    private let source: PlaycutSource

    /// Injectable seam for `concerts(forArtist:)`, parallel to `source` above.
    /// Defaults to an empty source, matching the safe-empty-default
    /// convention every F5x/OT query seam uses.
    private let concertSource: ConcertSource

    public init() {
        self.init(source: { [] }, concertSource: { [] })
    }

    public init(source: @escaping PlaycutSource, concertSource: @escaping ConcertSource = { [] }) {
        self.source = source
        self.concertSource = concertSource
    }

    /// Resolves `identifiers` to entities by deduping the source's playcuts
    /// down to one ArtistEntity per normalized artist name — each carrying
    /// the play count of its dedup group and displaying a representative
    /// original-cased name via `representativeName(in:)` (#646), the same
    /// selection rule `SpotlightDonationService.donateArtists` uses — then
    /// looking up each requested id. Preserves the input order and drops ids
    /// the source couldn't resolve, matching the AppIntents `entities(for:)`
    /// contract.
    public func entities(for identifiers: [ArtistID]) async throws -> [ArtistEntity] {
        let playcuts = await source()
        let entitiesByID = Dictionary(
            uniqueKeysWithValues: Self.groupedByNormalizedArtist(playcuts).map { normalized, group in
                (ArtistID(stableEntityID(for: normalized)), ArtistEntity(artistName: representativeName(in: group), playCount: group.count))
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

    /// This artist's upcoming curated concerts — the OT-C6 cross-link between
    /// the playlist graph and On Tour (WXYC/wxyc-ios-64#629). Resolves `id` to
    /// the WXYC catalog artist ids of its matching playcuts (via
    /// ``playcuts(forArtist:)``'s ``Playcut/artistId``), then filters the
    /// injected concert source down to concerts whose non-nil
    /// ``Concert/headliningArtistId`` is one of those catalog ids — the same
    /// id-only join ``ForYouShelf``'s loved tier uses, never falling back to
    /// name matching. An artist whose plays never resolved a catalog id
    /// (free-text plays, or a feed that predates the field) has nothing to
    /// intersect on and returns `[]` without consulting the concert source.
    public func concerts(forArtist id: ArtistID) async throws -> [Concert] {
        let matchingPlaycuts = try await playcuts(forArtist: id)
        let catalogArtistIDs = Set(matchingPlaycuts.compactMap(\.artistId))
        guard !catalogArtistIDs.isEmpty else { return [] }

        let concerts = await concertSource()
        return concerts.filter { concert in
            guard let headlinerID = concert.headliningArtistId else { return false }
            return catalogArtistIDs.contains(headlinerID)
        }
    }

    /// Groups `playcuts` by normalized artist name, using the normalized
    /// name itself (not the first-seen raw name) as the dictionary key so
    /// callers get a stable, already-normalized string back.
    private static func groupedByNormalizedArtist(_ playcuts: [Playcut]) -> [String: [Playcut]] {
        Dictionary(grouping: playcuts) { normalizedEntityKey($0.artistName) }
    }
}
