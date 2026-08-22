//
//  ForegroundSessionTrackerTests.swift
//  Core
//
//  Pins how a run of `ForegroundVisibility` transitions collapses into one
//  measured on-screen span. The rows that matter are the ones a naive
//  start-on-active/stop-on-inactive timer gets wrong: a Control Center pull
//  must not close or restart the span, and a launch straight into the
//  background must not report a session that never happened.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Core

@Suite("Foreground session tracker")
struct ForegroundSessionTrackerTests {

    /// One fixed origin every test advances from, so no assertion depends on
    /// how long the test itself took to run.
    private let origin = ContinuousClock.now

    @Test("An on-screen span is reported when the app leaves the screen")
    func onScreenThenOffScreenReportsTheSpan() {
        var tracker = ForegroundSessionTracker()

        #expect(tracker.record(.onScreen, at: origin) == nil)
        #expect(tracker.record(.offScreen, at: origin.advanced(by: .seconds(12))) == .seconds(12))
    }

    @Test("Leaving the screen without having been on it reports nothing")
    func offScreenWithoutOnScreenReportsNothing() {
        var tracker = ForegroundSessionTracker()

        // A background launch — a background refresh, a widget timeline
        // reload — never puts the app on screen, so there is no span to
        // report. Reporting a zero here would drag every distribution down.
        #expect(tracker.record(.offScreen, at: origin) == nil)
    }

    @Test("A transient interruption neither closes nor restarts the span")
    func noChangeLeavesTheSpanRunning() {
        var tracker = ForegroundSessionTracker()

        // The regression this exists to prevent: iOS delivers `.inactive` for
        // a Control Center pull with the app still on screen, and reading it
        // as a session boundary both truncates the real span and starts a
        // phantom second one. The whole 30 s must survive as one session.
        #expect(tracker.record(.onScreen, at: origin) == nil)
        #expect(tracker.record(.noChange, at: origin.advanced(by: .seconds(10))) == nil)
        #expect(tracker.record(.offScreen, at: origin.advanced(by: .seconds(30))) == .seconds(30))
    }

    @Test("Coming back on screen without having left keeps the original start")
    func repeatedOnScreenDoesNotRestartTheSpan() {
        var tracker = ForegroundSessionTracker()

        // `.active -> .inactive -> .active` (the dismissed Control Center
        // pull) classifies as on-screen, no-change, on-screen: the second
        // on-screen is not a new session, and treating it as one would report
        // 5 s for a 25 s visit.
        #expect(tracker.record(.onScreen, at: origin) == nil)
        #expect(tracker.record(.onScreen, at: origin.advanced(by: .seconds(20))) == nil)
        #expect(tracker.record(.offScreen, at: origin.advanced(by: .seconds(25))) == .seconds(25))
    }

    @Test("Each visit is measured on its own, not from the first one")
    func successiveSessionsMeasureIndependently() {
        var tracker = ForegroundSessionTracker()

        _ = tracker.record(.onScreen, at: origin)
        #expect(tracker.record(.offScreen, at: origin.advanced(by: .seconds(5))) == .seconds(5))

        _ = tracker.record(.onScreen, at: origin.advanced(by: .seconds(600)))
        #expect(tracker.record(.offScreen, at: origin.advanced(by: .seconds(607))) == .seconds(7))
    }

    @Test("A closed session is not reported twice")
    func offScreenAfterOffScreenReportsNothing() {
        var tracker = ForegroundSessionTracker()

        _ = tracker.record(.onScreen, at: origin)
        _ = tracker.record(.offScreen, at: origin.advanced(by: .seconds(3)))

        // Nothing puts the app back on screen in between, so there is no
        // second span — and certainly not one measured from the first start.
        #expect(tracker.record(.offScreen, at: origin.advanced(by: .seconds(9))) == nil)
    }

    @Test("A span that starts and ends in the same instant is still a session")
    func zeroLengthSpanIsReported() {
        var tracker = ForegroundSessionTracker()

        // Distinct from the `nil` above: the app *was* on screen, so this is a
        // real (if instantaneous) visit and belongs in the distribution.
        _ = tracker.record(.onScreen, at: origin)
        #expect(tracker.record(.offScreen, at: origin) == .zero)
    }
}
