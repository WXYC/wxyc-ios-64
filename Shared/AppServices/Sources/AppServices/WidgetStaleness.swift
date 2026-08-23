//
//  WidgetStaleness.swift
//  AppServices
//
//  Builds the timeline a now-playing entry renders on: current now, and — when
//  that is still ahead — stale at the moment it ages out.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// When the widget's now-playing data is old enough that showing it plainly
/// would be a lie.
///
/// The widget cannot refresh often enough to always be right — see
/// ``WidgetRefreshSchedule`` for why — so the remaining job is to be honest
/// about it, which ``renderSchedule(playedAt:from:)`` does without spending a
/// reload.
///
/// Age is measured from the playcut's broadcast time, not from when the
/// timeline was built: a widget that renders a track which aired 40 minutes
/// ago is 40 minutes stale, however recently it fetched.
public enum WidgetStaleness {

    /// One rendering of an entry: when to show it, and whether it still claims
    /// to be current at that point.
    public struct RenderStep: Sendable, Equatable {
        public let date: Date
        public let isStale: Bool

        public init(date: Date, isStale: Bool) {
            self.date = date
            self.isStale = isStale
        }
    }

    /// How long after broadcast an entry stops claiming to be current.
    ///
    /// Longer than every refresh tier but the coldest, so in normal operation
    /// a refresh lands first and the stale entry is never rendered. It exists
    /// for the case where refreshes stop coming. `WidgetStalenessTests` asserts
    /// that relationship against ``WidgetRefreshSchedule``'s tiers, since it
    /// spans two types and a comment cannot notice when one of them is retuned.
    static let threshold: TimeInterval = 45 * 60

    /// The entries a timeline should carry for a playcut broadcast at
    /// `playedAt`, starting from `now`.
    ///
    /// Always leads with an entry dated `now` — WidgetKit needs something to
    /// render the moment it takes the timeline. When the entry has not yet
    /// aged out, a second entry follows at its expiry, marked stale: WidgetKit
    /// renders that one on schedule from the timeline it already holds, so the
    /// widget visibly steps back from its claim even if the budget is spent
    /// and no refresh ever arrives.
    ///
    /// - Parameter playedAt: When the displayed playcut aired, or `nil` for
    ///   the placeholder and empty states — those have no data to be stale, and
    ///   dimming them would present "no data yet" as "stale data".
    /// - Returns: One or two steps, strictly ordered, never repeating a date.
    public static func renderSchedule(playedAt: Date?, from now: Date) -> [RenderStep] {
        guard let playedAt else {
            return [RenderStep(date: now, isStale: false)]
        }

        let expiry = playedAt.addingTimeInterval(threshold)

        // Strictly future, so the second entry can't collide with the one
        // already being rendered at `now`. An expiry that has passed (or falls
        // exactly on `now`) means the leading entry is itself the stale one,
        // and there is nothing left to say later.
        guard expiry > now else {
            return [RenderStep(date: now, isStale: true)]
        }

        return [
            RenderStep(date: now, isStale: false),
            RenderStep(date: expiry, isStale: true),
        ]
    }
}
