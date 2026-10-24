//
//  NowPlayingTimelineEntry.swift
//  WXYC
//
//  Timeline entry model for widget updates.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppServices
import Playlist
import SwiftUI
import WidgetKit

struct NowPlayingTimelineEntry: TimelineEntry {
    let date: Date
    let artist: String
    let songTitle: String
    let artwork: SwiftUI.Image?
    let recentItems: [NowPlayingItem]
    let family: WidgetFamily
    /// The specialty program on the air, when the layout names one: over the person, or as context for a song.
    let headline: NowPlayingHeadline?
    /// The program's logo, already downsampled to the family's pixel size. `nil` draws the tile.
    let programLogo: SwiftUI.Image?
    /// Whether the program headline leads (no song of this show yet), rather than a song with the program as context.
    let programLeads: Bool
    /// The who's-on entry's role label ("Live in the studio"), set only on a specialty who's-on entry. Medium and large draw it.
    let roleLabel: String?
    /// The freeform guest line ("In the studio: <name>") under a leading song, drawn by medium and large.
    let guestLine: String?
    /// The label over `recentItems`: "Before <short name>" while they belong to an earlier show.
    let recentsLabel: String

    /// A leading song, with `headline` as context when a specialty show is on the air and `guestLine`
    /// for a freeform show's guest.
    init(
        nowPlayingItem: NowPlayingItem,
        recentItems: [NowPlayingItem],
        family: WidgetFamily,
        headline: NowPlayingHeadline? = nil,
        logo: CGImage? = nil,
        guestLine: String? = nil,
        recentsLabel: String = NowPlayingTimelineEntry.defaultRecentsLabel
    ) {
        self.date = .now
        self.artist = nowPlayingItem.playcut.artistName
        self.songTitle = nowPlayingItem.playcut.songTitle

        if let artwork = nowPlayingItem.artwork {
            self.artwork = Image(uiImage: artwork)
        } else {
            self.artwork = nil
        }

        self.recentItems = headline == nil ? recentItems : Array(recentItems.prefix(WidgetContent.leadInProgram.recentLimit))
        self.family = family
        self.headline = headline
        self.programLogo = logo.map { Image(decorative: $0, scale: 1) }
        self.programLeads = false
        self.roleLabel = nil
        self.guestLine = guestLine
        self.recentsLabel = recentsLabel
    }

    /// A specialty show with no song of its own yet: the program takes the bold line over the person,
    /// the recents follow, and the logo (or the tile when `logo` is `nil`) is the artwork. `roleLabel` is set
    /// while a who's-on entry names the person.
    init(headline: NowPlayingHeadline, logo: CGImage?, recentItems: [NowPlayingItem], family: WidgetFamily, roleLabel: String? = nil, recentsLabel: String = NowPlayingTimelineEntry.defaultRecentsLabel) {
        self.date = .now
        self.artist = headline.program.name
        self.songTitle = headline.person
        self.artwork = nil
        self.recentItems = Array(recentItems.prefix(WidgetContent.program.recentLimit))
        self.family = family
        self.headline = headline
        self.programLogo = logo.map { Image(decorative: $0, scale: 1) }
        self.programLeads = true
        self.roleLabel = roleLabel
        self.guestLine = nil
        self.recentsLabel = recentsLabel
    }

    /// The line under the program and person: the role label with a who's-on entry, otherwise the program's tagline.
    var supportingLine: String? { roleLabel ?? headline?.tagline }

    static func placeholder(family: WidgetFamily) -> Self {
        NowPlayingTimelineEntry(
            nowPlayingItem: NowPlayingItem.placeholder,
            recentItems: [.placeholder, .placeholder, .placeholder],
            family: family
        )
    }
    
    static let defaultRecentsLabel = "Recently Played"

    /// The station line the widget shows when it has no song to name.
    private static let stationLineText = "Tune in to WXYC 89.3 FM"

    /// Creates an entry for when no song leads (automation, or a show with no song yet) but
    /// recents exist: the station line takes the bold lead line and the recents follow it.
    static func stationLine(recentItems: [NowPlayingItem], family: WidgetFamily) -> Self {
        NowPlayingTimelineEntry(
            artist: stationLineText,
            songTitle: "",
            artwork: nil,
            recentItems: recentItems,
            family: family
        )
    }

    /// Creates an entry for a leading freeform who's-on entry: the role line on the bold line over the DJ
    /// handle (the system Now Playing strings, bold line first), with the recents under it and no artwork,
    /// never the previous song's. A specialty show's entry uses the program initializer instead.
    static func whosOn(_ spotlight: NowPlayingSpotlight, recentItems: [NowPlayingItem], family: WidgetFamily) -> Self {
        NowPlayingTimelineEntry(
            artist: spotlight.title,
            songTitle: spotlight.artist,
            artwork: nil,
            recentItems: recentItems,
            family: family
        )
    }

    /// Creates an entry representing an empty playlist state.
    /// Used when the playlist service returns no playcuts.
    static func emptyState(family: WidgetFamily) -> Self {
        NowPlayingTimelineEntry(
            artist: "No Data Available",
            songTitle: stationLineText,
            artwork: nil,
            recentItems: [],
            family: family
        )
    }

    /// Private initializer for creating entries with raw values (used for empty state)
    private init(artist: String, songTitle: String, artwork: SwiftUI.Image?, recentItems: [NowPlayingItem], family: WidgetFamily) {
        self.date = .now
        self.artist = artist
        self.songTitle = songTitle
        self.artwork = artwork
        self.recentItems = recentItems
        self.family = family
        self.headline = nil
        self.programLogo = nil
        self.programLeads = false
        self.roleLabel = nil
        self.guestLine = nil
        self.recentsLabel = Self.defaultRecentsLabel
    }
}

extension NowPlayingTimelineEntry: SongDisplayable {
    /// Bridges `artist` onto `SongDisplayable`'s `artistName`, so `Header`,
    /// `MediumNowPlayingWidgetEntryView`, and `SmallNowPlayingWidgetEntryView`
    /// can feed the entry straight into `SongInfoColumn` instead of hand-rolling
    /// their own title/artist `Text` stack. `nonisolated` to satisfy
    /// `SongDisplayable`'s nonisolated requirement under this target's default
    /// `MainActor` isolation — `artist` is a plain `let`, so reading it off the
    /// main actor is safe.
    nonisolated var artistName: String { artist }

    /// The timeline entry carries no release field — always `nil`. Only
    /// affects `SongDisplayable.artworkCacheKey`, which the widget rows don't
    /// use (their artwork is pre-resolved into `artwork` by `Provider`).
    nonisolated var releaseTitle: String? { nil }
}
