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
        var nowPlayingItemsWithArtwork: [NowPlayingItem] = []
        // A failing fetch is swallowed into an empty playlist by
        // `PlaylistFetcher`, so an empty timeline and a broken one are
        // indistinguishable from the return value alone. The delta on the
        // fetcher's cumulative error count over this one call separates them.
        // Two synchronous actor reads, no network, no state of our own.
        var fetchFailed = false

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
            let errorsBefore = await playlistService.fetchErrorCount()
            nowPlayingItemsWithArtwork = await nowPlayingItems(from: playlistService.fetchPlaylist())
            fetchFailed = (await playlistService.fetchErrorCount()) > errorsBefore
        }

        let now = Date.now
        let entries: [NowPlayingTimelineEntry]
        let outcome: WidgetTimelineOutcome

        if let (nowPlayingItem, recentItems) = nowPlayingItemsWithArtwork.safePopFirst() {
            let recents = Array(recentItems)

            entries = [
                NowPlayingTimelineEntry(
                    nowPlayingItem: nowPlayingItem,
                    recentItems: recents,
                    family: family
                )
            ]
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
