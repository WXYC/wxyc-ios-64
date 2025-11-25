//
//  NowPlayingTimelineEntry.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import WidgetKit
import SwiftUI
import Core

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
}

