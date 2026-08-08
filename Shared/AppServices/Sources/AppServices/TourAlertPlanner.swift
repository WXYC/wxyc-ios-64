//
//  TourAlertPlanner.swift
//  AppServices
//
//  Pure decision + copy for the dev-only "artist on tour" lock-screen alert.
//  Reads the tour signal that already rides the on-air playcut
//  (`Playcut.upcomingShow`, joined server-side when the played artist matches a
//  curated upcoming concert), so no artist-id resolution or concerts scan is
//  needed. Kept separate from the notification API and the observing coordinator
//  so every branch — including the copy — is unit-testable.
//
//  Gated `#if !os(watchOS) && !os(tvOS)` because it reads `Concert` fields, and
//  `AppServices` conditions its `Concerts` dependency to iOS/macCatalyst/macOS.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)
import Concerts
import Core
import Foundation
import Playlist

/// Decides whether an on-air play warrants a tour alert and, if so, builds its
/// presented content.
public enum TourAlertPlanner {
    /// Returns the alert to post, or `nil` when no alert should fire.
    ///
    /// An alert fires only when the stream is playing, there is an on-air
    /// playcut, its artist has a resolved upcoming show, and that show hasn't
    /// already been alerted this session.
    /// - Parameters:
    ///   - isPlaying: Whether the live stream is currently playing.
    ///   - playcut: The on-air playcut (`playlist.playcuts.first`), or `nil`.
    ///   - upcomingShow: The resolved upcoming show for `playcut`, or `nil`.
    ///     Resolved by the caller (``TourAlertCoordinator``) so a DEBUG mock can
    ///     stand in for the embedded ``Playlist/Playcut/upcomingShow`` — see its
    ///     `resolveUpcomingShow` seam.
    ///   - alreadyNotified: Concert ids already alerted this session (de-dup).
    public static func plan(
        isPlaying: Bool,
        playcut: Playcut?,
        upcomingShow: Concert?,
        alreadyNotified: Set<Int>
    ) -> TourAlert? {
        guard isPlaying,
              let playcut,
              let show = upcomingShow,
              !alreadyNotified.contains(show.id)
        else {
            return nil
        }

        return TourAlert(
            concertID: show.id,
            artistName: playcut.artistName,
            title: "\(playcut.artistName) is on tour",
            body: body(for: show)
        )
    }

    private static func body(for show: Concert) -> String {
        let day = dayFormatter.string(from: show.startsOn)
        return "Playing on WXYC now — \(show.venue.name), \(show.venue.city) on \(day)"
    }

    /// `startsOn` is a date-only instant anchored to the station zone; format it
    /// with the station contract (`America/New_York`, `en_US_POSIX`) so the day
    /// label matches the Box Office ticket and never renders the previous day
    /// for a device west of Eastern.
    private static let dayFormatter = DateFormatter.station("EEE, MMM d")
}
#endif
