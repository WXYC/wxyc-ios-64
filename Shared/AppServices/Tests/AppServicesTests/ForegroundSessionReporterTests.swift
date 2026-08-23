//
//  ForegroundSessionReporterTests.swift
//  AppServices
//
//  Pins the composition that turns a run of visibility transitions into
//  `foreground_session` events: that a visit produces exactly one event, that
//  its duration is the tracker's span, and that `is_playing` describes the
//  moment the visit ended rather than the moment it began.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AnalyticsTesting
import Core
import Foundation
import Testing
@testable import AppServices

@MainActor
@Suite("Foreground session reporter")
struct ForegroundSessionReporterTests {

    /// One fixed origin every test advances from, so no assertion depends on
    /// how long the test itself took to run.
    private let origin = ContinuousClock.now

    @Test("A completed visit captures one event carrying its span")
    func completedVisitCapturesOneEvent() throws {
        let analytics = MockStructuredAnalytics()
        let reporter = ForegroundSessionReporter(analytics: analytics, isPlaying: { false })

        reporter.record(.onScreen, at: origin)
        #expect(analytics.typedEvents(ofType: ForegroundSession.self).isEmpty)

        reporter.record(.offScreen, at: origin.advanced(by: .seconds(12)))

        let events = analytics.typedEvents(ofType: ForegroundSession.self)
        #expect(events.count == 1)
        #expect(try #require(events.first).durationSeconds == 12)
    }

    @Test("A sub-second visit keeps its fractional seconds")
    func subSecondVisitKeepsItsFraction() throws {
        let analytics = MockStructuredAnalytics()
        let reporter = ForegroundSessionReporter(analytics: analytics, isPlaying: { false })

        // The `Duration` -> `TimeInterval` bridge is where a visit's fraction
        // can be lost, and the median visit is on the order of ten seconds.
        reporter.record(.onScreen, at: origin)
        reporter.record(.offScreen, at: origin.advanced(by: .milliseconds(1500)))

        let event = try #require(analytics.typedEvents(ofType: ForegroundSession.self).first)
        #expect(event.durationSeconds == 1.5)
    }

    @Test("is_playing describes the end of the visit, not its start", arguments: [true, false])
    func isPlayingIsSampledAtTheClosingEdge(playingAtEnd: Bool) throws {
        let analytics = MockStructuredAnalytics()
        // Starts at the opposite value and flips before the visit closes, so a
        // reporter that sampled at `.onScreen` — or captured the flag by value
        // at construction — reports the wrong one.
        var playing = !playingAtEnd
        let reporter = ForegroundSessionReporter(analytics: analytics, isPlaying: { playing })

        reporter.record(.onScreen, at: origin)
        playing = playingAtEnd
        reporter.record(.offScreen, at: origin.advanced(by: .seconds(3)))

        let event = try #require(analytics.typedEvents(ofType: ForegroundSession.self).first)
        #expect(event.isPlaying == playingAtEnd)
    }

    @Test("A transient interruption produces one event for the whole visit")
    func interruptionDoesNotSplitTheVisit() throws {
        let analytics = MockStructuredAnalytics()
        let reporter = ForegroundSessionReporter(analytics: analytics, isPlaying: { false })

        // A Control Center pull: on screen throughout, so the whole 30 s is
        // one visit. Reading `.noChange` as an exit reports two events.
        reporter.record(.onScreen, at: origin)
        reporter.record(.noChange, at: origin.advanced(by: .seconds(10)))
        reporter.record(.onScreen, at: origin.advanced(by: .seconds(20)))
        reporter.record(.offScreen, at: origin.advanced(by: .seconds(30)))

        let events = analytics.typedEvents(ofType: ForegroundSession.self)
        #expect(events.count == 1)
        #expect(try #require(events.first).durationSeconds == 30)
    }

    @Test("A launch that never reaches the screen captures nothing")
    func backgroundLaunchCapturesNothing() {
        let analytics = MockStructuredAnalytics()
        let reporter = ForegroundSessionReporter(analytics: analytics, isPlaying: { false })

        // A background refresh or widget timeline reload. A zero-length event
        // here would drag the whole distribution down.
        reporter.record(.offScreen, at: origin)

        #expect(analytics.typedEvents(ofType: ForegroundSession.self).isEmpty)
    }

    @Test("Each visit is captured separately, measured on its own")
    func successiveVisitsAreCapturedSeparately() {
        let analytics = MockStructuredAnalytics()
        let reporter = ForegroundSessionReporter(analytics: analytics, isPlaying: { false })

        reporter.record(.onScreen, at: origin)
        reporter.record(.offScreen, at: origin.advanced(by: .seconds(5)))
        reporter.record(.onScreen, at: origin.advanced(by: .seconds(600)))
        reporter.record(.offScreen, at: origin.advanced(by: .seconds(607)))

        let events = analytics.typedEvents(ofType: ForegroundSession.self)
        #expect(events.map(\.durationSeconds) == [5, 7])
    }
}
