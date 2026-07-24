//
//  ReleaseEntity.swift
//  Intents
//
//  App Intents bridge from a `Playcut.artistName`/`Playcut.releaseTitle` pair
//  to an addressable, Spotlight-indexable `AppEntity`. Mirrors ArtistEntity's
//  F5b shape: dedup by a normalized key only, no donation pipeline and no
//  richer per-release query.
//
//  A release title alone isn't a stable dedup key — different artists share
//  album titles — so the id is derived from a normalized COMPOSITE of both
//  halves, joined by a unit-separator character that can't appear in either
//  normalized string. Normalization and hashing reuse the shared
//  `normalizedEntityKey`/`stableEntityID` helpers in ArtistIdentity.swift
//  rather than inventing new ones.
//
//  `IndexedEntity` is gated to platforms where CoreSpotlight exists, matching
//  ArtistEntity/PlaycutEntity: `IndexedEntity`/`CSSearchableItemAttributeSet`
//  are both `@available(tvOS, unavailable)`, and watchOS doesn't ship
//  CoreSpotlight.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

public typealias ReleaseID = EntityID<ReleaseEntity>

public struct ReleaseEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Release",
        numericFormat: "\(placeholder: .int) releases"
    )

    public static let defaultQuery = ReleaseEntityQuery()

    public var id: ReleaseID

    /// The dedup key for the release title half of the composite — also the
    /// sole title text this minimal slice displays.
    @Property(title: "Release")
    public var normalizedReleaseTitle: String

    /// The dedup key for the artist half of the composite — displayed as the
    /// subtitle.
    @Property(title: "Artist")
    public var normalizedArtistName: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(normalizedReleaseTitle)", subtitle: "\(normalizedArtistName)")
    }

    /// Builds an entity from a raw `Playcut.artistName`/`Playcut.releaseTitle`
    /// pair. Two playcuts whose artist and release names differ only by a
    /// "feat. …" clause or casing/whitespace produce entities with identical
    /// `id`.
    public init(artistName: String, releaseTitle: String) {
        let normalizedArtist = normalizedEntityKey(artistName)
        let normalizedRelease = normalizedEntityKey(releaseTitle)
        let compositeKey = normalizedArtist + "\u{1f}" + normalizedRelease
        self.id = ReleaseID(stableEntityID(for: compositeKey))
        self.normalizedArtistName = normalizedArtist
        self.normalizedReleaseTitle = normalizedRelease
    }
}

#if !os(watchOS) && !os(tvOS)
extension ReleaseEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.title = normalizedReleaseTitle
        set.artist = normalizedArtistName
        set.relatedUniqueIdentifier = id.entityIdentifierString
        return set
    }
}
#endif
