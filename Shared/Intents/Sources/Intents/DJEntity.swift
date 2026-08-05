//
//  DJEntity.swift
//  Intents
//
//  App Intents bridge from `ShowMarker.djName` to an addressable,
//  Spotlight-indexable `AppEntity`, mirroring `ArtistEntity`. DJs are a
//  small, slow-changing set, so the identifier is derived from the
//  normalized DJ name rather than any backend row id — dedup by normalized
//  name only, no Contacts/IntentPerson bridge (that's CC-C1, tracked
//  separately) and no donation pipeline.
//
//  Dedup key and identifier derivation, the `displayRepresentation`, and the
//  `attributeSet` are all inherited from `NormalizedNameEntity`
//  (NormalizedNameEntity.swift) — `LabelEntity`'s pre-collapse body was
//  character-identical to this one modulo the noun ("DJ" vs "Label"), so
//  both conform there instead of repeating the plumbing. See that file for
//  why `String.hashValue` is unsafe for entity ids.
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

public typealias DJID = EntityID<DJEntity>

public struct DJEntity: NormalizedNameEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "DJ",
        numericFormat: "\(placeholder: .int) DJs"
    )

    public static let defaultQuery = DJEntityQuery()

    /// The dedup key ("Jake B" and "  jake   b  " both normalize to the
    /// same value) — also the sole text this minimal slice displays.
    @Property(title: "Name")
    public var normalizedName: String

    /// Builds an entity from a raw `ShowMarker.djName`. Two show markers
    /// whose DJ names differ only by casing or whitespace produce entities
    /// with identical `id` and `normalizedName`.
    public init(djName: String) {
        self.normalizedName = normalizedEntityKey(djName)
    }
}

#if !os(watchOS) && !os(tvOS)
extension DJEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        normalizedNameAttributeSet
    }
}
#endif
