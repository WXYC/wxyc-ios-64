//
//  PlaycutEntity.swift
//  Intents
//
//  App Intents bridge from a domain-model Playcut to a Spotlight-indexable
//  AppEntity. Deep-linking and index maintenance live in sibling files —
//  this type only mints the entity and its display representation.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import CoreSpotlight
import Foundation
import Playlist

public typealias PlaycutID = EntityID<PlaycutEntity>

public struct PlaycutEntity: AppEntity, IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Playcut",
        numericFormat: "\(placeholder: .int) playcuts"
    )

    public static let defaultQuery = PlaycutEntityQuery()

    public var id: PlaycutID

    @Property(title: "Title")
    public var title: String

    @Property(title: "Artist")
    public var artistName: String

    @Property(title: "Release")
    public var releaseTitle: String?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: releaseTitle.map { "\(artistName) — \($0)" } ?? "\(artistName)"
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .audio)
        set.title = title
        set.artist = artistName
        set.album = releaseTitle
        set.contentDescription = releaseTitle.map { "\(artistName) — \($0)" } ?? artistName
        return set
    }

    public init(playcut: Playcut) {
        self.id = PlaycutID(playcut.id)
        self.title = playcut.songTitle
        self.artistName = playcut.artistName
        self.releaseTitle = playcut.releaseTitle
    }
}
