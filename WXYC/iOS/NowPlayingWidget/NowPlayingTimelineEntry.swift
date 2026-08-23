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

    /// When the displayed playcut aired, or `nil` for the placeholder and
    /// empty states, which have no broadcast to age from.
    ///
    /// Drives the "played N minutes ago" label, which SwiftUI keeps counting
    /// up on its own — the widget's only continuously-honest surface between
    /// timeline entries, and the one that costs no reload.
    let playedAt: Date?

    /// Whether this entry should present its data as possibly out of date.
    ///
    /// Set on the trailing, future-dated entry `Provider` appends. See
    /// ``WidgetStaleness``.
    let isStale: Bool

    /// - Parameters:
    ///   - date: When this entry should be rendered. Defaults to now, which is
    ///     what every entry but the trailing stale one wants.
    ///   - isStale: Whether to render as possibly out of date.
    init(
        nowPlayingItem: NowPlayingItem,
        recentItems: [NowPlayingItem],
        family: WidgetFamily,
        date: Date = .now,
        isStale: Bool = false
    ) {
        self.date = date
        self.artist = nowPlayingItem.playcut.artistName
        self.songTitle = nowPlayingItem.playcut.songTitle
        self.playedAt = nowPlayingItem.playcut.broadcastDate
        self.isStale = isStale

        if let artwork = nowPlayingItem.artwork {
            self.artwork = Image(uiImage: artwork)
        } else {
            self.artwork = nil
        }

        self.recentItems = recentItems
        self.family = family
    }

    static func placeholder(family: WidgetFamily) -> Self {
        NowPlayingTimelineEntry(
            nowPlayingItem: NowPlayingItem.placeholder,
            recentItems: [.placeholder, .placeholder, .placeholder],
            family: family
        )
    }
    
    /// Creates an entry representing an empty playlist state.
    /// Used when the playlist service returns no playcuts.
    static func emptyState(family: WidgetFamily) -> Self {
        NowPlayingTimelineEntry(
            artist: "No Data Available",
            songTitle: "Tune in to WXYC 89.3 FM",
            artwork: nil,
            recentItems: [],
            family: family
        )
    }
    
    /// Private initializer for creating entries with raw values (used for empty state)
    ///
    /// These entries carry no playcut, so `playedAt` is `nil` and they are
    /// never stale: dimming "no data yet" would present it as stale data,
    /// which is a different and wronger message.
    private init(artist: String, songTitle: String, artwork: SwiftUI.Image?, recentItems: [NowPlayingItem], family: WidgetFamily) {
        self.date = .now
        self.artist = artist
        self.songTitle = songTitle
        self.artwork = artwork
        self.recentItems = recentItems
        self.family = family
        self.playedAt = nil
        self.isStale = false
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
