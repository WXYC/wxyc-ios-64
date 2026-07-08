//
//  PlaycutEntity.swift
//  Intents
//
//  App Intents bridge from a domain-model Playcut to a Spotlight-indexable
//  AppEntity. Carries the fields Spotlight and Siri need to present a rich
//  result (thumbnail, label, genre, broadcast time) so tapping a search hit
//  surfaces the same metadata the in-app detail view does.
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

    @Property(title: "Release Year")
    public var releaseYear: Int?

    /// Artwork URL — surfaced as the Spotlight thumbnail so results carry
    /// album art rather than a placeholder glyph.
    public let artworkURL: URL?

    /// Record label — surfaced in Spotlight via `recordLabel`.
    public let labelName: String?

    /// Discogs genre tags — the first one drives Spotlight's `genre` field.
    public let genres: [String]?

    /// Broadcast time as milliseconds since epoch. Derived once from
    /// `Playcut.hour` so `attributeSet` and `displayRepresentation` share the
    /// same date without recomputing.
    public let broadcastDate: Date

    /// Composed "artist — release" (or just "artist" when there is no
    /// release title). Computed once in `init` so the subtitle string and
    /// Spotlight's contentDescription share it.
    public let subtitleText: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitleText)"
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .audio)
        set.title = title
        set.artist = artistName
        set.album = releaseTitle
        set.genre = genres?.first
        set.thumbnailURL = artworkURL
        set.contentDescription = subtitleText
        set.contentCreationDate = broadcastDate
        // Ties the CoreSpotlight item back to the AppEntity so a Spotlight tap
        // resolves to this specific playcut via OpenPlaycut.
        set.relatedUniqueIdentifier = id.entityIdentifierString
        return set
    }

    public init(playcut: Playcut) {
        self.id = PlaycutID(playcut.id)
        self.artworkURL = playcut.artworkURL
        self.labelName = playcut.labelName
        self.genres = playcut.genres
        self.broadcastDate = Date(timeIntervalSince1970: TimeInterval(playcut.hour) / 1000)
        self.subtitleText = playcut.releaseTitle.map { "\(playcut.artistName) — \($0)" } ?? playcut.artistName
        self.title = playcut.songTitle
        self.artistName = playcut.artistName
        self.releaseTitle = playcut.releaseTitle
        self.releaseYear = playcut.releaseYear
    }
}
