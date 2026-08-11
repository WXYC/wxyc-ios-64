//
//  DJEntity.swift
//  Intents
//
//  App Intents bridge from `ShowMarker.djName` to an addressable,
//  Spotlight-indexable `AppEntity`, mirroring `ArtistEntity`. DJs are a
//  small, slow-changing set, so the identifier is derived from the
//  normalized DJ name rather than any backend row id — dedup by normalized
//  name only, no donation pipeline.
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
//  `intentPerson`/`from(intentPerson:)` below are CC-C1's `IntentPerson`
//  bridge — DJs are people-shaped, so Apple Intelligence should get to treat
//  them with the same conversational machinery it uses for contacts ("the DJ
//  named Brian"). The mapping itself is unconditional (`IntentPerson` has
//  shipped since iOS 16), but the `Transferable` conformance that wires it
//  into `IntentValueRepresentation` is `#if compiler(>=6.4)`-gated: that type
//  carries an `@available(iOS 26.4, *)` annotation but does not actually
//  exist in the stable Xcode 26.5 SDK's `AppIntents` module at all — only the
//  Xcode 27 beta toolchain's iOS 27.0 SDK declares it. Same shape as
//  `LiveRadioStationEntity`'s iOS 27 gate.
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

extension DJEntity {
    /// Exports this DJ as an `IntentPerson` (CC-C1) so Apple Intelligence can
    /// treat DJ names with the same conversational machinery it uses for
    /// contacts. `.applicationDefined` keeps the identifier out of the
    /// Contacts identifier space — DJs are commonly referred to by stage name
    /// only, so this is what stops "the DJ named Brian" from colliding with
    /// an address-book contact named Brian. `handle` stays `nil` until WXYC
    /// exposes a public-facing DJ handle; this bridge is scoped to letting
    /// the system *understand* DJ names, not to messaging affordances ("text
    /// DJ Brian").
    public var intentPerson: IntentPerson {
        IntentPerson(
            identifier: .applicationDefined(id.entityIdentifierString),
            name: .displayName(normalizedName),
            handle: nil
        )
    }

    /// The inverse of `intentPerson`. Only understands `.displayName` — the
    /// one shape `intentPerson` ever produces — because a `DJEntity` has
    /// nothing else to reconstruct from; a `.components` or `.unknown` name
    /// throws rather than fabricating a DJ from data this bridge never
    /// exported. Re-normalizing an already-normalized name through
    /// `DJEntity(djName:)` is a no-op (`normalizedEntityKey` is idempotent),
    /// so this round-trips to the entity that exported it.
    public static func from(intentPerson person: IntentPerson) throws -> DJEntity {
        guard case .displayName(let name) = person.name else {
            throw IntentPersonImportError.unsupportedName(person.name)
        }
        return DJEntity(djName: name)
    }

    public enum IntentPersonImportError: Swift.Error, Equatable {
        /// `person.name` wasn't `.displayName` — the only shape
        /// `intentPerson` exports, so this isn't a value this bridge produced.
        case unsupportedName(IntentPerson.Name)
    }
}

#if compiler(>=6.4)
import CoreTransferable

@available(iOS 26.4, macOS 26.4, watchOS 26.4, tvOS 26.4, *)
extension DJEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        IntentValueRepresentation(
            exporting: { dj in dj.intentPerson },
            importing: { person in try DJEntity.from(intentPerson: person) }
        )
    }
}
#endif
