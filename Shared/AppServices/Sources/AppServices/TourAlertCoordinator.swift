//
//  TourAlertCoordinator.swift
//  AppServices
//
//  The integration seam that pumps on-air playcuts into `TourAlertPlanner` and
//  forwards a decision to a `TourAlertScheduling`, holding the per-session
//  de-dup set so a track that stays on air across poll ticks (or repeats) alerts
//  once. Owns no notification API itself, so it is host-testable with a
//  recording scheduler double.
//
//  Gated `#if !os(watchOS) && !os(tvOS)` because it depends on `TourAlertPlanner`
//  (which reads `Concert`, unavailable on those platforms in this package).
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)
import Concerts
import Playlist

/// Drives the dev-only tour-alert feature: feed it the on-air playcut and the
/// current playback state on every poll tick; it posts at most one alert per
/// upcoming show per session.
@MainActor
public final class TourAlertCoordinator {
    private let scheduler: any TourAlertScheduling
    private let resolveUpcomingShow: @MainActor (Playcut) -> Concert?
    private var notifiedConcertIDs: Set<Int> = []

    /// - Parameters:
    ///   - scheduler: Posts the resolved alert to the platform.
    ///   - resolveUpcomingShow: Maps the on-air playcut to its upcoming show.
    ///     Defaults to the value the backend embedded on the feed
    ///     (`playcut.upcomingShow`). The app's `#if DEBUG` wiring overrides this
    ///     to honor the "Mock ticket on first item" debug toggle, so the same
    ///     affordance that fakes the Box Office ticket also drives a test alert.
    public init(
        scheduler: any TourAlertScheduling,
        resolveUpcomingShow: @escaping @MainActor (Playcut) -> Concert? = { $0.upcomingShow }
    ) {
        self.scheduler = scheduler
        self.resolveUpcomingShow = resolveUpcomingShow
    }

    /// Evaluates the current on-air play and posts a tour alert if one is
    /// warranted and not already sent this session.
    /// - Parameters:
    ///   - playcut: The on-air playcut (`playlist.currentPlaycut`), or `nil`.
    ///   - isPlaying: Whether the live stream is currently playing.
    public func ingest(playcut: Playcut?, isPlaying: Bool) async {
        // Call the resolver directly (not via `Optional.map`/`flatMap`): it is
        // `@MainActor`-isolated and those expect a non-isolated closure.
        let upcomingShow: Concert?
        if let playcut {
            upcomingShow = resolveUpcomingShow(playcut)
        } else {
            upcomingShow = nil
        }
        guard let alert = TourAlertPlanner.plan(
            isPlaying: isPlaying,
            playcut: playcut,
            upcomingShow: upcomingShow,
            alreadyNotified: notifiedConcertIDs
        ) else {
            return
        }

        // Record before awaiting the post so a re-entrant ingest for the same
        // show can't slip a duplicate through the guard.
        notifiedConcertIDs.insert(alert.concertID)
        await scheduler.post(alert)
    }
}
#endif
