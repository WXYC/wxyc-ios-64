//
//  WidgetRefreshScheduleTests.swift
//  AppServices
//
//  Tests for the budget-aware widget refresh cadence: the decay tiers, the
//  active-playback safety net, and the day-long budget bound that the tier
//  table exists to satisfy.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import AppServices

/// One minute and one hour, as concretely-typed constants.
///
/// Every duration below is written against these rather than as a bare
/// `29 * 60` literal chain: an untyped integer-literal product inside a tuple
/// array leaves the expression type-checker to solve the whole table at once,
/// which times out.
private nonisolated let minute: TimeInterval = 60
private nonisolated let hour: TimeInterval = 60 * 60

/// `(secondsSinceEngagement, expectedInterval, label)`.
///
/// Hoisted to a top-level `let` rather than written inline in the `arguments:`
/// label: a tuple array large enough to cover every tier boundary blows the
/// expression type-checker when it has to be inferred inside the macro.
private nonisolated let decayTierCases: [(TimeInterval, TimeInterval, String)] = [
    (0, 10 * minute, "just engaged"),
    (19 * minute, 10 * minute, "inside the hot window"),
    (20 * minute, 15 * minute, "hot boundary is exclusive"),
    (119 * minute, 15 * minute, "inside the warm window"),
    (2 * hour, 40 * minute, "warm boundary is exclusive"),
    (7 * hour, 40 * minute, "inside the cool window"),
    (8 * hour, 60 * minute, "cool boundary is exclusive"),
    (24 * hour, 60 * minute, "long past any engagement"),
]

/// Walks a simulated day, restarting the decay at each engagement, and counts
/// the budgeted reloads the tier table would request.
private nonisolated func reloadsRequested(overADayWith engagementHours: [TimeInterval]) -> Int {
    let dayStart = Date(timeIntervalSince1970: 1_800_000_000)
    let engagements = engagementHours.map { dayStart.addingTimeInterval($0 * hour) }
    let dayEnd = dayStart.addingTimeInterval(24 * hour)

    var clock = dayStart
    var reloads = 0

    while clock < dayEnd {
        // Whichever engagement is the most recent one to have happened by now.
        let lastEngagement = engagements.filter { $0 <= clock }.max()
        clock = clock.addingTimeInterval(
            WidgetRefreshSchedule.refreshInterval(
                now: clock,
                lastEngagement: lastEngagement,
                isPlaying: false
            )
        )
        reloads += 1
    }

    return reloads
}

@Suite("Widget Refresh Schedule", .timeLimit(.minutes(1)))
struct WidgetRefreshScheduleTests {

    // MARK: - Decay tiers

    @Test("Refresh interval decays as engagement recedes", arguments: decayTierCases)
    func intervalDecaysWithTimeSinceEngagement(
        secondsSinceEngagement: TimeInterval,
        expected: TimeInterval,
        label: String
    ) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lastEngagement = now.addingTimeInterval(-secondsSinceEngagement)

        let interval = WidgetRefreshSchedule.refreshInterval(
            now: now,
            lastEngagement: lastEngagement,
            isPlaying: false
        )

        #expect(interval == expected, "\(label)")
    }

    @Test("Never-engaged devices get the coldest tier")
    func neverEngagedGetsColdestInterval() {
        let interval = WidgetRefreshSchedule.refreshInterval(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            lastEngagement: nil,
            isPlaying: false
        )

        #expect(interval == 60 * 60)
    }

    @Test("A future engagement timestamp is treated as the hot tier, not the cold one")
    func clockSkewDoesNotColdStartTheWidget() {
        // A clock adjustment (or a write from a device in another time zone
        // via the shared app group) can leave `lastEngagement` ahead of `now`.
        // Negative elapsed time must not fall through the `<` comparisons into
        // the coldest bucket — the user engaged, that is what the value means.
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let interval = WidgetRefreshSchedule.refreshInterval(
            now: now,
            lastEngagement: now.addingTimeInterval(5 * 60),
            isPlaying: false
        )

        #expect(interval == 10 * 60)
    }

    // MARK: - Active playback

    @Test("Active playback stretches to the safety net instead of the hot tier")
    func activePlaybackUsesSafetyNetInterval() {
        // While playback is live, `WidgetStateService` reloads on every
        // flowsheet change for free (the audio session exempts them from the
        // budget), so the timeline's own schedule is only a backstop against
        // the process dying mid-session. Spending the hot tier here would
        // double-charge the budget for updates already arriving.
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let interval = WidgetRefreshSchedule.refreshInterval(
            now: now,
            lastEngagement: now,
            isPlaying: true
        )

        #expect(interval == 30 * 60)
    }

    @Test("The safety net still applies when engagement is cold")
    func activePlaybackNeverGoesColderThanSafetyNet() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let interval = WidgetRefreshSchedule.refreshInterval(
            now: now,
            lastEngagement: now.addingTimeInterval(-24 * 60 * 60),
            isPlaying: true
        )

        #expect(interval == 30 * 60)
    }

    // MARK: - Budget

    @Test("A day of typical engagement stays inside the reload budget")
    func dailyReloadCountFitsBudget() {
        // WidgetKit grants roughly 40-70 budgeted reloads per widget instance
        // per day. That ceiling is the constraint the whole tier table exists
        // to satisfy, so it is asserted rather than left to arithmetic in a
        // design doc: loosening any tier fails here first.
        //
        // Three engagements — morning, lunch, evening — currently requests 49.
        // The bound is deliberately tighter than the 70 ceiling so there is
        // visible headroom for the heavier days below, which are allowed to
        // exceed it.
        let reloads = reloadsRequested(overADayWith: [8, 12, 18])

        #expect(reloads <= 60, "requested \(reloads) reloads/day, over the intended typical-day bound")
    }

    @Test("An untouched device costs almost nothing")
    func idleDayCostsAlmostNothing() {
        // The case the old flat 5-minute policy handled worst: a widget on a
        // home screen page nobody visits, quietly asking for 288 reloads a day
        // and being throttled for it.
        let reloads = reloadsRequested(overADayWith: [])

        #expect(reloads == 24)
    }

    @Test("A heavy-engagement day overruns the ceiling, and that is the intended trade")
    func heavyEngagementOverrunsCeilingByDesign() {
        // Each engagement restarts the decay, so a user who opens the app ten
        // times a day asks for more budgeted reloads than WidgetKit will grant
        // — no tier tuning avoids that, it is inherent to decaying from
        // engagement. It is the right trade anyway: that user is foregrounding
        // the app ten times, and every one of those reloads is exempt from the
        // budget (see `WidgetStateService`), so their widget is already being
        // refreshed for free. The budgeted reloads WidgetKit declines are the
        // ones they need least.
        //
        // Pinned so the overrun stays a known, bounded consequence rather than
        // something discovered in the field.
        let reloads = reloadsRequested(overADayWith: [7, 8, 9, 11, 13, 15, 17, 19, 21, 22])

        #expect(reloads > 70)
        #expect(reloads < 100, "requested \(reloads) reloads/day — the overrun should stay bounded")
    }

    @Test("The tier table never requests a reload faster than WidgetKit coalesces")
    func noTierIsFasterThanTheCoalescingFloor() {
        // WidgetKit coalesces timeline entries spaced under ~5 minutes, so any
        // tier tighter than that spends budget for an update the system will
        // not deliver on time anyway.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let offsets: [TimeInterval] = [0, 30 * minute, 2 * hour, 8 * hour, 48 * hour]

        for offset in offsets {
            for isPlaying in [true, false] {
                let interval = WidgetRefreshSchedule.refreshInterval(
                    now: now,
                    lastEngagement: now.addingTimeInterval(-offset),
                    isPlaying: isPlaying
                )
                #expect(interval >= 5 * 60, "offset \(offset), isPlaying \(isPlaying)")
            }
        }
    }
}
