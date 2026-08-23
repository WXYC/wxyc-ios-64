//
//  WidgetRefreshSchedule.swift
//  AppServices
//
//  Resolves how far out a widget timeline should schedule its next budgeted
//  reload, decaying the cadence as the user's last engagement recedes.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The cadence at which the now-playing widget asks WidgetKit for its next
/// timeline.
///
/// WidgetKit grants each widget instance roughly **40-70 budgeted reloads per
/// 24 hours** — about one every 20-35 minutes. WXYC turns over 10-15 playcuts
/// an hour, so no budgeted schedule can track the flowsheet play-for-play; a
/// flat short interval just gets throttled by the system, spending the whole
/// budget before the day is out and leaving the widget stale for the rest of
/// it.
///
/// This decays instead. Engagement — foregrounding the app, starting playback,
/// tapping the widget's own button — restarts a tight cadence, which then cools
/// off as that engagement recedes. The user who checked the app five minutes
/// ago gets a widget that keeps up; the user who last opened it yesterday
/// spends almost nothing. `WidgetRefreshScheduleTests` pins the resulting
/// day-long reload count under the budget ceiling.
///
/// This is deliberately the *budgeted* path only. The far fresher updates come
/// from reloads the system does not charge for — see ``WidgetStateService``,
/// which reloads on every flowsheet change while the audio session is live.
public enum WidgetRefreshSchedule {

    // MARK: - Tiers

    /// Cadence right after the user engaged.
    public static let hotInterval: TimeInterval = 10 * 60
    /// Cadence through the first couple of hours after engagement.
    public static let warmInterval: TimeInterval = 15 * 60
    /// Cadence through the rest of the user's active day.
    public static let coolInterval: TimeInterval = 30 * 60
    /// Cadence once engagement is stale, and for devices that have never
    /// recorded any.
    public static let coldInterval: TimeInterval = 60 * 60

    /// Backstop cadence while playback is active.
    ///
    /// Not the hot tier, deliberately: during playback ``WidgetStateService``
    /// is already reloading on every flowsheet change for free, so a tight
    /// timeline here would charge the budget a second time for updates that
    /// have already arrived. This exists only so a session that ends with the
    /// process being killed — where no foreground reload ever comes — still has
    /// a scheduled refresh pending.
    public static let activePlaybackInterval: TimeInterval = 30 * 60

    // MARK: - Tier boundaries

    private static let hotWindow: TimeInterval = 30 * 60
    private static let warmWindow: TimeInterval = 2 * 60 * 60
    private static let coolWindow: TimeInterval = 8 * 60 * 60

    // MARK: - Resolution

    /// How long to wait before the next budgeted timeline reload.
    ///
    /// - Parameters:
    ///   - now: The current instant.
    ///   - lastEngagement: When the user last engaged, or `nil` if no
    ///     engagement has ever been recorded — treated as the coldest tier,
    ///     since there is no evidence any budget spent here would be seen.
    ///   - isPlaying: Whether playback is currently active.
    /// - Returns: The interval to pass to WidgetKit's `.after` reload policy.
    public static func refreshInterval(
        now: Date,
        lastEngagement: Date?,
        isPlaying: Bool
    ) -> TimeInterval {
        if isPlaying {
            return activePlaybackInterval
        }

        guard let lastEngagement else {
            return coldInterval
        }

        // A negative elapsed time means `lastEngagement` sits in the future —
        // reachable through a clock adjustment, or a write from another device
        // in the shared app group. It falls into the hot tier rather than
        // through every `..<` into the cold one, which is the right reading:
        // the timestamp's existence is itself the engagement signal.
        return switch now.timeIntervalSince(lastEngagement) {
        case ..<hotWindow: hotInterval
        case ..<warmWindow: warmInterval
        case ..<coolWindow: coolInterval
        default: coldInterval
        }
    }

    /// The date to hand WidgetKit's `.after` reload policy.
    ///
    /// See ``refreshInterval(now:lastEngagement:isPlaying:)`` for the parameters.
    public static func nextRefreshDate(
        now: Date,
        lastEngagement: Date?,
        isPlaying: Bool
    ) -> Date {
        now.addingTimeInterval(
            refreshInterval(now: now, lastEngagement: lastEngagement, isPlaying: isPlaying)
        )
    }
}
