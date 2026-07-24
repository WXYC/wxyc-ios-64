//
//  LabelEntity.swift
//  Intents
//
//  App Intents bridge from a `Playcut.labelName` string to an addressable,
//  Spotlight-indexable `AppEntity`. Backs NC/indie label discovery ("what has
//  WXYC played on Trekky Records?") for CC-F2 secondary entities. F5d is
//  deliberately minimal: dedup by normalized label name only, no donation
//  pipeline and no richer per-label query.
//
//  Displays the librarian filing (the raw `Playcut.labelName` string) rather
//  than reconciling with a Discogs-canonical label name — that reconciliation
//  is the open product decision tracked in #292, out of scope here.
//
//  Dedup key and identifier derivation are shared with every other F5x
//  string-keyed entity via `normalizedEntityKey`/`stableEntityID` in
//  ArtistIdentity.swift — see that file for why `String.hashValue` is unsafe
//  here.
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

public typealias LabelID = EntityID<LabelEntity>

public struct LabelEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Label",
        numericFormat: "\(placeholder: .int) labels"
    )

    public static let defaultQuery = LabelEntityQuery()

    public var id: LabelID

    /// The dedup key (label-name casing/whitespace variants normalize to the
    /// same value) — also the sole text this minimal slice displays.
    @Property(title: "Name")
    public var normalizedName: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(normalizedName)")
    }

    /// Builds an entity from a raw `Playcut.labelName`. Two playcuts whose
    /// label names differ only by casing/whitespace produce entities with
    /// identical `id` and `normalizedName`.
    public init(labelName: String) {
        let normalized = normalizedEntityKey(labelName)
        self.id = LabelID(stableEntityID(for: normalized))
        self.normalizedName = normalized
    }
}

#if !os(watchOS) && !os(tvOS)
extension LabelEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.title = normalizedName
        set.relatedUniqueIdentifier = id.entityIdentifierString
        return set
    }
}
#endif
