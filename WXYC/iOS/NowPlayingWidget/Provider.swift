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
        // Constructed AFTER PostHog setup, deliberately: `PlaylistService.init`
        // resolves `PlaylistAPIVersion.loadActive()` synchronously, and a
        // stored-property default runs before this init body — pre-setup,
        // `getFeatureFlag` returns nil unconditionally, deterministically
        // pinning every widget process to `defaultVersion`. This fixes the
        // ordering only: the widget's PostHog flag cache is per-container (no
        // `appGroupIdentifier` is configured), so it still can't see the main
        // app's flag values — but per-version cache keys
        // (`PlaylistCacheKey.playlist(for:)`) keep a v1-resolving widget from
        // poisoning the app's v2 cache either way.
        playlistService = PlaylistService()
    }

    /// The four most recent playcuts as artwork-resolved items, head first.
    ///
    /// The head comes from `Playlist.currentPlaycut` — the same accessor every
    /// other now-playing surface reads (see its doc for the cases where it
    /// disagrees with a plain sort) — and the remaining three follow display
    /// order. One derivation for both `snapshot` and `timeline`, so the
    /// widget can't drift from the app's head-selection rule again.
    private func nowPlayingItems(from playlist: Playlist) async -> [NowPlayingItem] {
        guard let head = playlist.currentPlaycut else { return [] }
        let recent = playlist.playcuts
            .sorted(by: >)
            .filter { $0.id != head.id }
            .prefix(3)
        return await ([head] + recent).asyncMap { playcut in
            NowPlayingItem(
                playcut: playcut,
                artwork: try? await self.artworkService.fetchArtwork(for: playcut).toUIImage()
            )
        }
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

        var nowPlayingItems = await nowPlayingItems(from: playlistService.fetchPlaylist())

        // Handle empty playlist gracefully with empty state
        guard let (nowPlayingItem, recentItems) = nowPlayingItems.safePopFirst() else {
            return .emptyState(family: family)
        }

        return NowPlayingTimelineEntry(
            nowPlayingItem: nowPlayingItem,
            recentItems: Array(recentItems),
            family: family
        )
    }

    func timeline(for configuration: NowPlayingWidgetIntent, in context: Context) async -> Timeline<NowPlayingTimelineEntry> {
        let family = context.family
        StructuredPostHogAnalytics.shared.capture(WidgetGetTimeline(
            family: String(describing: family)
        ))

        var nowPlayingItemsWithArtwork: [NowPlayingItem] = []

        if context.isPreview {
            // Four literal evaluations, not `Array(repeating:)`: `.placeholder`
            // advances a rotating fixture per evaluation, while `repeating`
            // evaluates once and yields four rows sharing one `playcut.id` —
            // the key `LargeNowPlayingWidgetEntryView`'s `ForEach` requires to
            // be unique. Same form `placeholder(in:)` uses.
            nowPlayingItemsWithArtwork = [.placeholder, .placeholder, .placeholder, .placeholder]
        } else {
            // Already head-first — no re-sort here: sorting by the ordering
            // key would displace the `currentPlaycut` head exactly in the
            // cases where the two disagree.
            nowPlayingItemsWithArtwork = await nowPlayingItems(from: playlistService.fetchPlaylist())
        }

        let now = Date.now
        let entries: [NowPlayingTimelineEntry]

        if let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.safePopFirst() {
            let recents = Array(recentItems)
            let playedAt = nowPlayingItem.playcut.broadcastDate

            let current = NowPlayingTimelineEntry(
                nowPlayingItem: nowPlayingItem,
                recentItems: recents,
                family: family,
                date: now,
                isStale: WidgetStaleness.isStale(playedAt: playedAt, asOf: now)
            )

            // A second, future-dated entry so the widget can admit it has gone
            // stale without spending a reload to say so: WidgetKit renders it
            // on schedule from the timeline it already holds. In normal
            // operation the refresh below lands first and this is never shown
            // — it is the honest fallback for when the budget is spent.
            if let staleDate = WidgetStaleness.staleDate(playedAt: playedAt, after: now) {
                entries = [current, NowPlayingTimelineEntry(
                    nowPlayingItem: nowPlayingItem,
                    recentItems: recents,
                    family: family,
                    date: staleDate,
                    isStale: true
                )]
            } else {
                entries = [current]
            }
        } else {
            entries = [.emptyState(family: family)]
        }

        // Budget-aware, not fixed: a flat short interval asks for ~288 reloads
        // a day against a ceiling of 40-70, so WidgetKit throttles it and the
        // app loses all say in *when* the surviving reloads land. See
        // `WidgetRefreshSchedule`. The far fresher updates come from the
        // budget-exempt reloads `WidgetStateService` issues while the audio
        // session is live.
        let engagement = WidgetEngagementStore()
        let nextRefresh = WidgetRefreshSchedule.nextRefreshDate(
            now: now,
            lastEngagement: engagement.lastEngagement,
            isPlaying: engagement.isPlaying
        )
        return Timeline(entries: entries, policy: .after(nextRefresh))
    }
}
