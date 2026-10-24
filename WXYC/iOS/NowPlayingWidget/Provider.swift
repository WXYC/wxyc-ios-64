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

    /// What the widget shows for a playlist: what leads, the leading song as an artwork-resolved
    /// item when one does, the who's-on strings when an entry does, and up to three recents.
    private struct WidgetItems {
        var lead: NowPlayingLead
        var leadItem: NowPlayingItem?
        var whosOn: NowPlayingSpotlight?
        var recents: [NowPlayingItem]
        /// The specialty show on the air, with the DJ handle as its person line.
        var headline: NowPlayingHeadline?
        /// The program's logo decoded no larger than the family needs; `nil` draws the tile.
        var logo: CGImage?
    }

    /// The longest side, in pixels, of the logo the family draws: its tile or badge, never the full-size file.
    private static func logoPixelSize(for family: WidgetFamily) -> Int {
        family == .systemSmall ? 240 : 300
    }

    /// The lead comes from `Playlist.nowPlayingLead` — the rule every other now-playing
    /// surface reads — so a previous show's last song is never named as playing now. The
    /// recents skip the leader, or are the newest three when no song leads. One derivation
    /// for both `snapshot` and `timeline`.
    private func nowPlayingItems(from playlist: Playlist, family: WidgetFamily) async -> WidgetItems {
        let lead = playlist.nowPlayingLead
        let leadPlaycut: Playcut? = switch lead {
        case .song(let playcut): playcut
        case .spotlight, .specialtyCard, .djHandle, .nothing: nil
        }
        let recents = Playlist.widgetRecents(of: playlist.playcuts, lead: lead)
        let items = await ([leadPlaycut].compactMap { $0 } + recents).asyncMap { playcut in
            NowPlayingItem(
                playcut: playcut,
                artwork: try? await self.artworkService.fetchArtwork(for: playcut).toUIImage()
            )
        }
        let leadItem = leadPlaycut == nil ? nil : items.first
        let card = playlist.specialtyCard
        // Large keeps its layout until #1217, so only the other families get a headline (which selects the
        // program layouts and trims the recents) and a logo.
        let usesProgramLayouts = family != .systemLarge && family != .systemExtraLarge
        let headline = usesProgramLayouts ? card.map { NowPlayingHeadline(program: $0.program, person: $0.djHandle) } : nil
        let logo = if let headline {
            await SpecialtyArtwork.logo(for: headline.program, maxPixelSize: Self.logoPixelSize(for: family))
        } else {
            nil as CGImage?
        }
        return WidgetItems(
            lead: lead,
            leadItem: leadItem,
            whosOn: playlist.nowPlayingSpotlight,
            recents: leadItem == nil ? items : Array(items.dropFirst()),
            headline: headline,
            logo: logo
        )
    }

    /// The entry for a derived lead and recents, or nil when there is nothing to show.
    private func entry(_ items: WidgetItems, family: WidgetFamily) -> NowPlayingTimelineEntry? {
        switch Playlist.widgetContent(lead: items.lead, hasRecents: !items.recents.isEmpty, program: items.headline?.program) {
        case .lead:
            items.leadItem.map { NowPlayingTimelineEntry(nowPlayingItem: $0, recentItems: items.recents, family: family) }
        case .leadInProgram:
            items.leadItem.map {
                NowPlayingTimelineEntry(nowPlayingItem: $0, recentItems: items.recents, family: family, headline: items.headline, logo: items.logo)
            }
        case .program:
            items.lead.headline(person: items.headline?.person ?? "").map {
                NowPlayingTimelineEntry(headline: $0, logo: items.logo, recentItems: items.recents, family: family)
            }
        case .whosOn:
            items.whosOn.map { NowPlayingTimelineEntry.whosOn($0, recentItems: items.recents, family: family) }
        case .stationLine:
            .stationLine(recentItems: items.recents, family: family)
        case .empty:
            nil
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

        let items = await nowPlayingItems(from: playlistService.fetchPlaylist(), family: family)

        // Handle empty playlist gracefully with empty state
        return entry(items, family: family) ?? .emptyState(family: family)
    }

    func timeline(for configuration: NowPlayingWidgetIntent, in context: Context) async -> Timeline<NowPlayingTimelineEntry> {
        let family = context.family
        var items = WidgetItems(lead: .nothing, leadItem: nil, whosOn: nil, recents: [], headline: nil, logo: nil)
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
            let placeholder = NowPlayingItem.placeholder
            items = WidgetItems(
                lead: .song(placeholder.playcut),
                leadItem: placeholder,
                whosOn: nil,
                recents: [.placeholder, .placeholder, .placeholder],
                headline: nil,
                logo: nil
            )
        } else {
            let errorsBefore = await playlistService.fetchErrorCount()
            items = await nowPlayingItems(from: playlistService.fetchPlaylist(), family: family)
            fetchFailed = (await playlistService.fetchErrorCount()) > errorsBefore
        }

        let now = Date.now
        let entries: [NowPlayingTimelineEntry]
        let outcome: WidgetTimelineOutcome

        if let entry = entry(items, family: family) {
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
