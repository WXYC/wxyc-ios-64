//
//  NormalizedNameEntity.swift
//  Intents
//
//  Shared init/ID/attribute-set plumbing for AppEntity types keyed on a
//  single normalized string dedup key with nothing else to carry — today,
//  `DJEntity` and `LabelEntity`, whose pre-collapse bodies were
//  character-identical modulo the noun ("DJ" vs "Label"). A conforming type
//  supplies only `normalizedName` (its own dedup key, exposed as an
//  `@Property` so Siri can resolve on it) and gets `id`, `displayRepresentation`,
//  and (on platforms with CoreSpotlight) `attributeSet` for free.
//
//  Types with more to carry than a single normalized string — ArtistEntity's
//  original-cased `displayName`/`playCount`, ReleaseEntity's two-part
//  (artist, release) composite key — don't conform here; their
//  `displayRepresentation` and `attributeSet` genuinely differ from this
//  minimal shape rather than merely repeating it, so they reuse the
//  underlying `normalizedEntityKey`/`stableEntityID` helpers from
//  ArtistIdentity.swift directly instead.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

public protocol NormalizedNameEntity: AppEntity where ID == EntityID<Self> {
    /// The dedup key ("Jake B" and "  jake   b  " both normalize to the same
    /// value) — also the sole text this minimal shape displays.
    var normalizedName: String { get }
}

extension NormalizedNameEntity {
    /// Derived from `normalizedName` via the same FNV-1a hash every other
    /// string-keyed entity uses (`ArtistIdentity.swift`) — never
    /// `String.hashValue`, which is randomized per process launch and would
    /// break "ids stable across launches."
    public var id: EntityID<Self> {
        EntityID(stableEntityID(for: normalizedName))
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(normalizedName)")
    }
}

#if !os(watchOS) && !os(tvOS)
extension NormalizedNameEntity {
    /// A minimal `CSSearchableItemAttributeSet` carrying just a title and the
    /// id round-trip Spotlight needs to resolve a tap back to this entity.
    /// Named distinctly from `attributeSet` (rather than satisfying
    /// `IndexedEntity`'s requirement directly here) because `IndexedEntity`
    /// itself already ships a protocol-extension default `attributeSet` —
    /// providing a second one at the same protocol-extension tier makes the
    /// witness ambiguous. Each conforming type's own
    /// `extension X: IndexedEntity { public var attributeSet: ... }` calls
    /// through to this instead, the same way its pre-collapse body built the
    /// set inline.
    public var normalizedNameAttributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.title = normalizedName
        set.relatedUniqueIdentifier = id.entityIdentifierString
        return set
    }
}
#endif
