//
//  ShowEntity.swift
//  Intents
//
//  App Intents bridge from a domain-model ShowMarker (a DJ's sign-on) to a
//  Spotlight-indexable AppEntity, mirroring `PlaycutEntity`. Carries just
//  enough to present a minimal Siri/Spotlight result — DJ name as title,
//  the show's message as an optional subtitle — for a single airing.
//
//  The `IndexedEntity` conformance and the `CoreSpotlight`-backed
//  `attributeSet` are gated to platforms where CoreSpotlight exists, exactly
//  like `PlaycutEntity`'s gate.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Playlist
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

public typealias ShowID = EntityID<ShowEntity>

public struct ShowEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Show",
        numericFormat: "\(placeholder: .int) shows"
    )

    public static let defaultQuery = ShowEntityQuery()

    public var id: ShowID

    @Property(title: "DJ")
    public var djName: String

    /// The show marker's message, surfaced as the display subtitle. `nil`
    /// when the marker carries no message (an empty string, e.g. an unnamed
    /// sign-on), so the subtitle line disappears rather than showing blank.
    public let subtitleText: String?

    public var displayRepresentation: DisplayRepresentation {
        if let subtitleText {
            DisplayRepresentation(title: "\(djName)", subtitle: "\(subtitleText)")
        } else {
            DisplayRepresentation(title: "\(djName)")
        }
    }

    /// - Parameters:
    ///   - start: The airing's sign-on `ShowMarker`. Its `id` — the backend
    ///     id for that marker row — becomes the entity's identity, since a
    ///     sign-on and its matching sign-off carry distinct ids.
    public init(start: ShowMarker) {
        self.subtitleText = start.message.isEmpty ? nil : start.message
        self.id = ShowID(start.id)
        self.djName = start.onAirTitle
    }
}

#if !os(watchOS) && !os(tvOS)
extension ShowEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .audio)
        set.title = djName
        set.contentDescription = subtitleText
        set.relatedUniqueIdentifier = id.entityIdentifierString
        return set
    }
}
#endif
