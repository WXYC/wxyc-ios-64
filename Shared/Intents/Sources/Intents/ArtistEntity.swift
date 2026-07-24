//
//  ArtistEntity.swift
//  Intents
//
//  App Intents bridge from a `Playcut.artistName` string to an addressable,
//  Spotlight-indexable `AppEntity`. Backs CC-C5 "your favorite artist is
//  playing" notifications (attached to `UNMutableNotificationContent`) and
//  CC-F2 secondary entities. F5b landed the minimal dedup-only shape; C6
//  adds the donation pipeline (`SpotlightDonationService.donateArtists`,
//  AppServices), the richer per-artist query
//  (`ArtistEntityQuery.playcuts(forArtist:)`), and the `playCount` carried
//  here.
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
//  `playCount` is deliberately never persisted on the entity across
//  donations — `ArtistEntityQuery`/`SpotlightDonationService` recompute it
//  from the live playcut cache on every donation, so it's always the
//  current count as of that donation, not a stale snapshot from whenever
//  the entity was first indexed.
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

    /// Count of playcuts matching this artist's normalized name, as of the
    /// donation/query that produced this value. Drives Spotlight's
    /// per-artist ranking via ``playCountKey`` — see the file header for why
    /// this is never persisted independently of the source it was computed
    /// from.
    public var playCount: Int

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(normalizedName)")
    }

    /// Builds an entity from a raw `Playcut.artistName`. Two playcuts whose
    /// artist names differ only by a "feat. …" clause or casing/whitespace
    /// produce entities with identical `id` and `normalizedName`. `playCount`
    /// defaults to 0 for callers (like the F5b dedup-only path) that don't
    /// have a play count to report.
    public init(artistName: String, playCount: Int = 0) {
        let normalized = normalizedEntityKey(artistName)
        self.id = ArtistID(stableEntityID(for: normalized))
        self.playCount = playCount
        self.normalizedName = normalized
    }
}

#if !os(watchOS) && !os(tvOS)
extension ArtistEntity: IndexedEntity {
    /// Custom Spotlight attribute carrying `playCount` so a per-artist
    /// search can be ranked/filtered by play frequency. `CSCustomAttributeKey`'s
    /// initializer is failable (empty `keyName` is the only failure mode,
    /// which can't happen for this literal), so this is a `static let`
    /// rather than a force-unwrapped constant. `nonisolated(unsafe)` because
    /// `CSCustomAttributeKey` predates `Sendable`; the value is an immutable
    /// constant computed once at first access, so there's no actual shared
    /// mutable state to race on.
    public nonisolated(unsafe) static let playCountKey = CSCustomAttributeKey(
        keyName: "playCount",
        searchable: true,
        searchableByDefault: false,
        unique: false,
        multiValued: false
    )

    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.title = normalizedName
        // \.artist — the richer per-artist indexing key C6 adds so this
        // entity is discoverable under the same "artist" search facet
        // PlaycutEntity already populates.
        set.artist = normalizedName
        set.relatedUniqueIdentifier = id.entityIdentifierString
        if let playCountKey = Self.playCountKey {
            set.setValue(NSNumber(value: playCount), forCustomKey: playCountKey)
        }
        return set
    }
}
#endif
