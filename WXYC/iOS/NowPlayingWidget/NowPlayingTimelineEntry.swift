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
    let date: Date = Date()
    let artist: String
    let songTitle: String
    let artwork: SwiftUI.Image?
    let recentItems: [NowPlayingItem]
    let family: WidgetFamily

    init(nowPlayingItem: NowPlayingItem, recentItems: [NowPlayingItem], family: WidgetFamily) {
        self.artist = nowPlayingItem.playcut.artistName
        self.songTitle = nowPlayingItem.playcut.songTitle
        
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
    private init(artist: String, songTitle: String, artwork: SwiftUI.Image?, recentItems: [NowPlayingItem], family: WidgetFamily) {
        self.artist = artist
        self.songTitle = songTitle
        self.artwork = artwork
        self.recentItems = recentItems
        self.family = family
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
