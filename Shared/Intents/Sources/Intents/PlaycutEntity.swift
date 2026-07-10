//
//  PlaycutEntity.swift
//  Intents
//
//  App Intents bridge from a domain-model Playcut to a Spotlight-indexable
//  AppEntity. Carries the fields Spotlight and Siri need to present a rich
//  result (thumbnail, label as searchable keyword, genre, broadcast time) so
//  tapping a search hit surfaces the same metadata the in-app detail view does.
//
//  The `IndexedEntity` conformance and the `CoreSpotlight`-backed `attributeSet`
//  are gated to platforms where CoreSpotlight exists. `IndexedEntity` and
//  `CSSearchableItemAttributeSet` are both `@available(tvOS, unavailable)`,
//  and watchOS doesn't ship CoreSpotlight at all.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Playlist
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

public typealias PlaycutID = EntityID<PlaycutEntity>

public struct PlaycutEntity: AppEntity {
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

    /// Record label. Surfaced as a Spotlight `keywords` entry (there is no
    /// dedicated label field on `CSSearchableItemAttributeSet`) so a search
    /// for the label matches this playcut.
    public let labelName: String?

    /// Discogs genre tags — the first one drives Spotlight's `genre` field
    /// and every tag is added to `keywords`.
    public let genres: [String]?

    /// Broadcast time as a Swift `Date`, derived once from `Playcut.hour`
    /// (which is milliseconds since epoch) so `attributeSet` doesn't have
    /// to redo the conversion.
    public let broadcastDate: Date

    /// Composed "artist — release" (or just "artist" when there is no
    /// release title) so the subtitle string and Spotlight's
    /// contentDescription share it without re-formatting.
    public let subtitleText: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitleText)"
        )
    }

    public init(playcut: Playcut) {
        self.id = PlaycutID(playcut.id)
        self.artworkURL = playcut.artworkURL
        self.labelName = playcut.labelName
        self.genres = playcut.genres
        self.broadcastDate = playcut.broadcastDate
        let nonEmptyRelease = playcut.releaseTitle.flatMap { $0.isEmpty ? nil : $0 }
        self.subtitleText = nonEmptyRelease.map { "\(playcut.artistName) — \($0)" } ?? playcut.artistName
        self.title = playcut.songTitle
        self.artistName = playcut.artistName
        self.releaseTitle = playcut.releaseTitle
        self.releaseYear = playcut.releaseYear
    }
}

#if !os(watchOS) && !os(tvOS)
extension PlaycutEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .audio)
        set.title = title
        set.artist = artistName
        set.album = releaseTitle
        set.genre = genres?.first
        set.thumbnailURL = artworkURL
        set.contentDescription = subtitleText
        set.contentCreationDate = broadcastDate
        let labelKeyword = labelName.flatMap { $0.isEmpty ? nil : $0 }
        set.keywords = [labelKeyword].compactMap { $0 } + (genres ?? [])
        // Ties the CoreSpotlight item back to the AppEntity so a Spotlight tap
        // resolves to this specific playcut via OpenPlaycut.
        set.relatedUniqueIdentifier = id.entityIdentifierString
        return set
    }
}
#endif
