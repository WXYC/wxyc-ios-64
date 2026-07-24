//
//  ArtistEntity.swift
//  Intents
//
//  App Intents bridge from a `Playcut.artistName` string to an addressable,
//  Spotlight-indexable `AppEntity`. Backs CC-C5 "your favorite artist is
//  playing" notifications (attached to `UNMutableNotificationContent`) and
//  CC-F2 secondary entities. F5b is deliberately minimal: dedup by normalized
//  name only, no donation pipeline and no richer per-artist query (that's C6,
//  tracked separately).
//
//  Dedup key and identifier derivation are shared with every other F5x
//  string-keyed entity via `normalizedEntityKey`/`stableEntityID` in
//  ArtistIdentity.swift — see that file for why `String.hashValue` is unsafe
//  here.
//
//  `IndexedEntity` is gated to platforms where CoreSpotlight exists, matching
//  PlaycutEntity: `IndexedEntity`/`CSSearchableItemAttributeSet` are both
//  `@available(tvOS, unavailable)`, and watchOS doesn't ship CoreSpotlight.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

public typealias ArtistID = EntityID<ArtistEntity>

public struct ArtistEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Artist",
        numericFormat: "\(placeholder: .int) artists"
    )

    public static let defaultQuery = ArtistEntityQuery()

    public var id: ArtistID

    /// The dedup key ("Stereolab" and "Stereolab feat. …" both normalize to
    /// the same value) — also the sole text this minimal slice displays.
    @Property(title: "Name")
    public var normalizedName: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(normalizedName)")
    }

    /// Builds an entity from a raw `Playcut.artistName`. Two playcuts whose
    /// artist names differ only by a "feat. …" clause or casing/whitespace
    /// produce entities with identical `id` and `normalizedName`.
    public init(artistName: String) {
        let normalized = normalizedEntityKey(artistName)
        self.id = ArtistID(stableEntityID(for: normalized))
        self.normalizedName = normalized
    }
}

#if !os(watchOS) && !os(tvOS)
extension ArtistEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.title = normalizedName
        set.relatedUniqueIdentifier = id.entityIdentifierString
        return set
    }
}
#endif
