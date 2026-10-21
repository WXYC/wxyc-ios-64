//
//  Provider.swift
//  WXYC
//
//  Timeline provider for widget refresh.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import AppServices
import Artwork
import Caching
import Core
import Playlist
import PostHog
import SwiftUI
import WidgetKit

final class Provider: AppIntentTimelineProvider, Sendable {
    typealias Entry = NowPlayingTimelineEntry
    typealias Intent = NowPlayingWidgetIntent

    // Widget extensions run in a separate process from the main app.
    // They cannot access the main app's SwiftUI environment, so they
    // must create their own PlaylistService instance.
    let playlistService: PlaylistService
    let artworkService = MultisourceArtworkService()

    init() {
        let config = PostHogConfig(
            apiKey: AppConfiguration.defaults.posthogApiKey,
            host: AppConfiguration.defaults.posthogHost
        )
        PostHogSDK.shared.setup(config)
        // Constructed after PostHog setup rather than as a stored-property
        // default. The ordering used to be load-bearing — `PlaylistService.init`
        // resolved a PostHog-flag-backed API version synchronously, so a
        // pre-setup construction pinned every widget process to the compiled
        // default. That flag lookup went with the v1 path (#262), so the
        // constraint is gone; the placement is kept because the widget's
        // PostHog flag cache is still per-container (no `appGroupIdentifier`
        // is configured) and other flag reads may yet follow.
        playlistService = PlaylistService()
    }

    /// The widget entry for a playlist, or `nil` when it has no content (the empty state).
    ///
    /// The lead comes from `Playlist.nowPlayingLead` — the same function every other
    /// now-playing surface reads — so a song leads only when it belongs to the open show.
    /// When no song leads (automation, or a new show before its first song) the entry is
    /// led by the DJ, the specialty show, or the automation line, and the recent songs
    /// stay listed under it.
    private func entry(from playlist: Playlist, family: WidgetFamily) async -> NowPlayingTimelineEntry? {
        guard !playlist.isContentEmpty else { return nil }
        let lead = playlist.nowPlayingLead
        var playcuts = playlist.widgetRecents
        if case .song(let head) = lead {
            playcuts.insert(head, at: 0)
        }
        let items = await playcuts.asyncMap { playcut in
            NowPlayingItem(
                playcut: playcut,
                artwork: try? await self.artworkService.fetchArtwork(for: playcut).toUIImage()
            )
        }
        if let headline = lead.headline {
            return NowPlayingTimelineEntry(headline: headline, recentItems: items, family: family)
        }
        guard let head = items.first else { return nil }
        return NowPlayingTimelineEntry(nowPlayingItem: head, recentItems: Array(items.dropFirst()), family: family)
    }

    func placeholder(in context: Context) -> NowPlayingTimelineEntry {
        var nowPlayingItemsWithArtwork: [NowPlayingItem] = [
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
            NowPlayingItem.placeholder,
        ]

        guard let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.safePopFirst() else {
            return .placeholder(family: context.family)
        }

        return NowPlayingTimelineEntry(
            nowPlayingItem: nowPlayingItem,
            recentItems: Array(recentItems),
            family: context.family
        )
    }

    func snapshot(for configuration: NowPlayingWidgetIntent, in context: Context) async -> NowPlayingTimelineEntry {
        let family = context.family
        StructuredPostHogAnalytics.shared.capture(WidgetGetSnapshot(
            family: String(describing: family)
        ))

        // Handle empty playlist gracefully with empty state
        return await entry(from: playlistService.fetchPlaylist(), family: family) ?? .emptyState(family: family)
    }

    func timeline(for configuration: NowPlayingWidgetIntent, in context: Context) async -> Timeline<NowPlayingTimelineEntry> {
        let family = context.family
        var resolved: NowPlayingTimelineEntry?
        // A failing fetch is swallowed into an empty playlist by
        // `PlaylistFetcher`, so an empty timeline and a broken one are
        // indistinguishable from the return value alone. The delta on the
        // fetcher's cumulative error count over this one call separates them.
        // Two synchronous actor reads, no network, no state of our own.
        var fetchFailed = false

        if context.isPreview {
            // `placeholder(family:)` builds its own four rows, each a fresh
            // rotating fixture, so the large widget's `ForEach` keys stay unique.
            resolved = .placeholder(family: family)
        } else {
            let errorsBefore = await playlistService.fetchErrorCount()
            resolved = await entry(from: playlistService.fetchPlaylist(), family: family)
            fetchFailed = (await playlistService.fetchErrorCount()) > errorsBefore
        }

        let now = Date.now
        let entries: [NowPlayingTimelineEntry]
        let outcome: WidgetTimelineOutcome

        if let resolved {
            // A show-led entry (no song yet) is still a rendered entry, not `.empty`.
            entries = [resolved]
            outcome = .ok
        } else {
            entries = [.emptyState(family: family)]
            outcome = fetchFailed ? .fetchFailed : .empty
        }

        // Gated, not unconditional: WidgetKit picks the refresh cadence, so a
        // capture on every timeline is a per-timer emission. `init?` yields nil
        // for `.ok`, which is the overwhelming majority. See the event's doc
        // comment for what that costs a reader (WXYC/wxyc-ios-64#1065).
        if let event = WidgetGetTimeline(family: String(describing: family), outcome: outcome) {
            StructuredPostHogAnalytics.shared.capture(event)
        }

        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60)))
    }
}
