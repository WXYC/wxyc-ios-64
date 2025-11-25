//
//  Provider.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import WidgetKit
import SwiftUI
import Core
import PostHog
import Secrets
import Analytics

final class Provider: TimelineProvider, Sendable {
    typealias Entry = NowPlayingTimelineEntry
    
    // Widget extensions run in a separate process from the main app.
    // They cannot access the main app's SwiftUI environment, so they
    // must create their own PlaylistService instance.
    let playlistService = PlaylistService()
    let artworkService = MultisourceArtworkService()
    
    init() {
        let POSTHOG_API_KEY = Secrets.posthogApiKey
        let POSTHOG_HOST = "https://us.i.posthog.com"
        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)
        PostHogSDK.shared.setup(config)
    }
    
    func placeholder(in context: Context) -> NowPlayingTimelineEntry {
        var nowPlayingItemsWithArtwork: [NowPlayingItem] = [
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
        ]
        
        let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.popFirst()

        return NowPlayingTimelineEntry(
            nowPlayingItem: nowPlayingItem,
            recentItems: recentItems,
            family: context.family
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping @Sendable (NowPlayingTimelineEntry) -> ()) {
        let family = context.family
        PostHogSDK.shared.capture(
            "getSnapshot",
            context: "NowPlayingWidget",
            additionalData: ["family" : String(describing: family)]
        )

        Task {
            let playlist = await playlistService
                .updates()
                .first()
            
            guard let playlist else {
                let entry = NowPlayingTimelineEntry(
                    nowPlayingItem: .placeholder,
                    recentItems: [],
                    family: context.family
                )
                completion(entry)
                return
            }
            
            var nowPlayingItems = await playlist.playcuts
                .sorted(by: >)
                .prefix(4)
                .asyncMap { playcut in
                    NowPlayingItem(
                        playcut: playcut,
                        artwork: try? await self.artworkService.fetchArtwork(for: playcut)
                    )
                }

            let (nowPlayingItem, recentItems) = nowPlayingItems.popFirst()
            let entry = NowPlayingTimelineEntry(
                nowPlayingItem: nowPlayingItem,
                recentItems: recentItems,
                family: context.family
            )

            completion(entry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> ()) {
        let family = context.family
        PostHogSDK.shared.capture(
            "getTimeline",
            context: "NowPlayingWidget",
            additionalData: ["family" : String(describing: family)]
        )

        Task {
            var nowPlayingItemsWithArtwork: [NowPlayingItem] = []
            var entry: NowPlayingTimelineEntry = .placeholder(family: family)

            if context.isPreview {
                nowPlayingItemsWithArtwork = Array(repeating: .placeholder, count: 4)
            } else {
                let playlist = await playlistService.updates().first()
                
                if let playlist = playlist {
                    let playcuts = playlist
                        .playcuts
                        .sorted(by: >)
                        .prefix(4)

                    nowPlayingItemsWithArtwork = await playcuts.asyncMap { playcut in
                        NowPlayingItem(
                            playcut: playcut,
                            artwork: try? await self.artworkService.fetchArtwork(for: playcut)
                        )
                    }
                }
            }

            if nowPlayingItemsWithArtwork.count > 0 {
                nowPlayingItemsWithArtwork.sort(by: >)
                let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.popFirst()
                
                entry = NowPlayingTimelineEntry(
                    nowPlayingItem: nowPlayingItem,
                    recentItems: recentItems,
                    family: context.family
                )
            }
            
            // Schedule the next update
            let fiveMinutes = Date.now.addingTimeInterval(5 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(fiveMinutes))
            completion(timeline)
        }
    }
}

