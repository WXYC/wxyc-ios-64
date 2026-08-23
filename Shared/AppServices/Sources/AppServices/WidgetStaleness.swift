//
//  WidgetStaleness.swift
//  AppServices
//
//  Decides when a now-playing widget entry should stop presenting itself as
//  current, and when to schedule the entry that says so.
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
/// about it. Two things do that, and neither costs a reload:
///
/// - The rendered "played N minutes ago" label, which SwiftUI keeps counting
///   up on its own between timeline entries.
/// - A second, future-dated timeline entry carrying ``isStale`` — WidgetKit
///   renders it on schedule from the timeline it already holds, so the widget
///   visibly steps back from its claim even if the budget is spent and no
///   refresh ever arrives.
///
/// Age is measured from the playcut's broadcast time, not from when the
/// timeline was built: a widget that renders a track which aired 40 minutes
/// ago is 40 minutes stale, however recently it fetched.
public enum WidgetStaleness {

    /// How long after broadcast an entry stops claiming to be current.
    ///
    /// Longer than every refresh tier but the coldest, so in normal operation
    /// a refresh lands first and the stale entry is never rendered. It exists
    /// for the case where refreshes stop coming.
    public static let threshold: TimeInterval = 45 * 60

    /// Whether an entry showing a playcut broadcast at `playedAt` should
    /// present itself as out of date at `asOf`.
    ///
    /// - Parameters:
    ///   - playedAt: When the displayed playcut aired, or `nil` for the
    ///     placeholder and empty states, which have no data to be stale.
    ///   - asOf: The instant being rendered.
    public static func isStale(playedAt: Date?, asOf: Date) -> Bool {
        guard let playedAt else { return false }
        return asOf.timeIntervalSince(playedAt) >= threshold
    }

    /// The future instant at which this entry goes stale, if that is still
    /// ahead of `now`.
    ///
    /// - Returns: The date to give the trailing timeline entry, or `nil` when
    ///   there is nothing to schedule — either the entry has no broadcast time
    ///   or it is already stale as rendered, in which case the leading entry
    ///   carries ``isStale`` itself and a second one would add nothing.
    public static func staleDate(playedAt: Date?, after now: Date) -> Date? {
        guard let playedAt else { return nil }
        let expiry = playedAt.addingTimeInterval(threshold)
        // Strictly future: an entry dated `now` would collide with the one
        // already being rendered at `now`.
        return expiry > now ? expiry : nil
    }
}
