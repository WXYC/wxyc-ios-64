//
//  WidgetStalenessTests.swift
//  AppServices
//
//  Tests for the timeline a now-playing entry renders on: when it still claims
//  to be current, and the future-dated entry that lets it stop claiming
//  without spending a reload.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import AppServices

@Suite("Widget Staleness", .timeLimit(.minutes(1)))
struct WidgetStalenessTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - A fresh entry

    @Test("A fresh playcut renders current now and stale at its expiry")
    func freshPlaycutSchedulesItsOwnExpiry() throws {
        // The whole trick: the second entry costs no reload — WidgetKit
        // renders it on schedule from the timeline it already holds — so the
        // widget can admit it is out of date even when the budget is spent
        // and no refresh ever arrives.
        let schedule = WidgetStaleness.renderSchedule(playedAt: now, from: now)

        #expect(schedule == [
            .init(date: now, isStale: false),
            .init(date: now.addingTimeInterval(WidgetStaleness.threshold), isStale: true),
        ])
    }

    @Test("A playcut just under the threshold is still current, and still schedules its expiry")
    func playcutUnderThresholdIsNotStale() throws {
        let playedAt = now.addingTimeInterval(-WidgetStaleness.threshold + 60)

        let schedule = WidgetStaleness.renderSchedule(playedAt: playedAt, from: now)

        #expect(schedule.count == 2)
        #expect(schedule.first?.isStale == false)
        #expect(schedule.last?.date == now.addingTimeInterval(60))
        #expect(schedule.last?.isStale == true)
    }

    // MARK: - An already-stale entry

    @Test("A playcut past the threshold renders stale immediately, with nothing to schedule")
    func playcutPastThresholdIsStaleWithNoSecondEntry() throws {
        // A second entry would be dated in the past. The leading entry carries
        // the staleness itself, so there is nothing left to say later.
        let playedAt = now.addingTimeInterval(-WidgetStaleness.threshold - 1)

        let schedule = WidgetStaleness.renderSchedule(playedAt: playedAt, from: now)

        #expect(schedule == [.init(date: now, isStale: true)])
    }

    @Test("An entry expiring exactly now renders stale, with nothing to schedule")
    func entryExpiringAtNowSchedulesNothing() throws {
        // The boundary that used to live in the gap between two functions —
        // one comparing `>=`, the other `>`. A second entry dated `now` would
        // collide with the one already being rendered at `now`, so the tie
        // resolves to a single stale entry.
        let playedAt = now.addingTimeInterval(-WidgetStaleness.threshold)

        let schedule = WidgetStaleness.renderSchedule(playedAt: playedAt, from: now)

        #expect(schedule == [.init(date: now, isStale: true)])
    }

    // MARK: - No broadcast time

    @Test("Without a broadcast time the entry renders once and never claims staleness")
    func missingBroadcastTimeRendersOneCurrentEntry() throws {
        // The empty-state and placeholder entries carry no playcut. Dimming
        // them would present "no data yet" as "stale data", which is a
        // different and wronger message.
        let schedule = WidgetStaleness.renderSchedule(playedAt: nil, from: now)

        #expect(schedule == [.init(date: now, isStale: false)])
    }

    // MARK: - Invariants

    @Test("Every schedule leads with an entry dated now")
    func scheduleAlwaysLeadsWithNow() throws {
        // WidgetKit needs something to render at the moment the timeline is
        // handed over; a schedule that started in the future would leave the
        // widget showing its previous entry.
        let offsets: [TimeInterval] = [0, 60, WidgetStaleness.threshold, WidgetStaleness.threshold + 60]

        for offset in offsets {
            let schedule = WidgetStaleness.renderSchedule(
                playedAt: now.addingTimeInterval(-offset),
                from: now
            )
            #expect(schedule.first?.date == now, "offset \(offset)")
            #expect(schedule.isEmpty == false, "offset \(offset)")
        }
    }

    @Test("Entries are strictly ordered and never repeat a date")
    func scheduleIsStrictlyOrdered() throws {
        let schedule = WidgetStaleness.renderSchedule(playedAt: now, from: now)

        let dates = schedule.map(\.date)
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
    }

    @Test("The staleness threshold sits between the cool and cold refresh tiers")
    func thresholdSitsBetweenTheRefreshTiers() throws {
        // `threshold` is chosen to be longer than every refresh tier but the
        // coldest, so in normal operation a refresh lands before the stale
        // entry is ever rendered. That relationship spans two types, so it is
        // asserted rather than left to a comment that cannot notice when
        // someone retunes a tier.
        #expect(WidgetStaleness.threshold > WidgetRefreshSchedule.coolInterval)
        #expect(WidgetStaleness.threshold < WidgetRefreshSchedule.coldInterval)
    }
}
