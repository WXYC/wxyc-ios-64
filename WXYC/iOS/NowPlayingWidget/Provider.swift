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

    /// The leading song, if one leads, and up to three recents, as artwork-resolved items.
    ///
    /// The lead comes from `Playlist.nowPlayingLead` — the rule every other now-playing
    /// surface reads — so a previous show's last song is never named as playing now. The
    /// recents skip the leader, or are the newest three when no song leads. One derivation
    /// for both `snapshot` and `timeline`.
    private func nowPlayingItems(from playlist: Playlist) async -> (lead: NowPlayingItem?, recents: [NowPlayingItem]) {
        let lead = playlist.nowPlayingLead
        var leadPlaycut: Playcut?
        if case .song(let playcut) = lead {
            leadPlaycut = playcut
        }
        let recents = Playlist.widgetRecents(of: playlist.playcuts, lead: lead)
        let items = await ([leadPlaycut].compactMap { $0 } + recents).asyncMap { playcut in
            NowPlayingItem(
                playcut: playcut,
                artwork: try? await self.artworkService.fetchArtwork(for: playcut).toUIImage()
            )
        }
        return leadPlaycut == nil ? (nil, items) : (items.first, Array(items.dropFirst()))
    }

    /// The entry for a derived lead and recents, or nil when there is nothing to show.
    private func entry(
        lead: NowPlayingItem?,
        recents: [NowPlayingItem],
        family: WidgetFamily
    ) -> NowPlayingTimelineEntry? {
        if let lead {
            return NowPlayingTimelineEntry(nowPlayingItem: lead, recentItems: recents, family: family)
        }
        if !recents.isEmpty {
            return .stationLine(recentItems: recents, family: family)
        }
        return nil
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

        let (lead, recents) = await nowPlayingItems(from: playlistService.fetchPlaylist())

        // Handle empty playlist gracefully with empty state
        return entry(lead: lead, recents: recents, family: family) ?? .emptyState(family: family)
    }

    func timeline(for configuration: NowPlayingWidgetIntent, in context: Context) async -> Timeline<NowPlayingTimelineEntry> {
        let family = context.family
        var lead: NowPlayingItem?
        var recents: [NowPlayingItem] = []
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
            lead = .placeholder
            recents = [.placeholder, .placeholder, .placeholder]
        } else {
            let errorsBefore = await playlistService.fetchErrorCount()
            (lead, recents) = await nowPlayingItems(from: playlistService.fetchPlaylist())
            fetchFailed = (await playlistService.fetchErrorCount()) > errorsBefore
        }

        let now = Date.now
        let entries: [NowPlayingTimelineEntry]
        let outcome: WidgetTimelineOutcome

        if let entry = entry(lead: lead, recents: recents, family: family) {
            entries = [entry]
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
