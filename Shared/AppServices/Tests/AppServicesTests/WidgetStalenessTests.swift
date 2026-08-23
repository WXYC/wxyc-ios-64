//
//  WidgetStalenessTests.swift
//  AppServices
//
//  Tests for when a now-playing widget entry stops claiming to be current,
//  including the future-dated entry that lets it say so without spending a
//  reload.
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

    // MARK: - isStale

    @Test("A just-broadcast playcut is current")
    func freshPlaycutIsNotStale() {
        #expect(WidgetStaleness.isStale(playedAt: now, asOf: now) == false)
    }

    @Test("A playcut just under the threshold is still current")
    func playcutUnderThresholdIsNotStale() {
        let playedAt = now.addingTimeInterval(-WidgetStaleness.threshold + 60)

        #expect(WidgetStaleness.isStale(playedAt: playedAt, asOf: now) == false)
    }

    @Test("A playcut past the threshold is stale")
    func playcutPastThresholdIsStale() {
        let playedAt = now.addingTimeInterval(-WidgetStaleness.threshold - 1)

        #expect(WidgetStaleness.isStale(playedAt: playedAt, asOf: now))
    }

    @Test("Without a broadcast time nothing is claimed either way")
    func missingBroadcastTimeIsNotStale() {
        // The empty-state and placeholder entries carry no playcut. Dimming
        // them would present "no data yet" as "stale data", which is a
        // different and wronger message.
        #expect(WidgetStaleness.isStale(playedAt: nil, asOf: now) == false)
    }

    // MARK: - staleDate

    @Test("A fresh entry schedules the moment it will go stale")
    func freshEntrySchedulesItsOwnExpiry() {
        // This is the whole trick: a second, future-dated entry costs no
        // reload — WidgetKit renders it on time from the timeline it already
        // has — so the widget can admit it is out of date even when the
        // budget is exhausted and no refresh ever arrives.
        let staleDate = WidgetStaleness.staleDate(playedAt: now, after: now)

        #expect(staleDate == now.addingTimeInterval(WidgetStaleness.threshold))
    }

    @Test("An entry that renders already-stale schedules nothing")
    func alreadyStaleEntrySchedulesNothing() {
        let playedAt = now.addingTimeInterval(-WidgetStaleness.threshold - 60)

        #expect(WidgetStaleness.staleDate(playedAt: playedAt, after: now) == nil)
    }

    @Test("An entry that goes stale exactly now schedules nothing")
    func entryExpiringAtNowSchedulesNothing() {
        // A timeline entry dated `now` races the entry already being rendered
        // at `now`; WidgetKit wants strictly future dates, so this boundary
        // resolves to "no second entry" rather than a duplicate.
        let playedAt = now.addingTimeInterval(-WidgetStaleness.threshold)

        #expect(WidgetStaleness.staleDate(playedAt: playedAt, after: now) == nil)
    }

    @Test("Without a broadcast time there is nothing to schedule")
    func missingBroadcastTimeSchedulesNothing() {
        #expect(WidgetStaleness.staleDate(playedAt: nil, after: now) == nil)
    }

    // MARK: - Consistency

    @Test("The scheduled date is exactly when isStale flips")
    func scheduledDateAgreesWithIsStale() throws {
        // The two functions are read by the same timeline — one picks the
        // entry's date, the other its rendered state — so a disagreement would
        // show up as an entry that renders dimmed while still claiming to be
        // current, or the reverse.
        let playedAt = now.addingTimeInterval(-10 * 60)
        let flip = try #require(WidgetStaleness.staleDate(playedAt: playedAt, after: now))

        #expect(WidgetStaleness.isStale(playedAt: playedAt, asOf: flip.addingTimeInterval(-1)) == false)
        #expect(WidgetStaleness.isStale(playedAt: playedAt, asOf: flip))
    }
}
