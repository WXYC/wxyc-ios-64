//
//  NowPlayingTimelineEntry.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import WidgetKit
import SwiftUI
import AppServices

struct NowPlayingTimelineEntry: TimelineEntry {
    let date: Date = Date(timeIntervalSinceNow: 1)
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

