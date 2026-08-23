//
//  ForegroundSessionReporter.swift
//  AppServices
//
//  Turns a run of `ForegroundVisibility` transitions into `foreground_session`
//  events. The measurement itself lives in Core's `ForegroundSessionTracker`,
//  which cannot report anything — an Analytics edge there would put PostHog in
//  the build graph of every package that imports Core — so the composition
//  lands at the lowest layer that already has both.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Core
import Foundation

/// Reports how long the app spends on screen, one visit at a time.
///
/// Feed it every ``ForegroundVisibility`` the app classifies, in order; it
/// captures one `foreground_session` on each transition that ends a visit and
/// stays silent on every other one. The rules about which transitions those
/// are — a Control Center pull is inside a visit, a launch that never reached
/// the screen ends no visit — belong to ``ForegroundSessionTracker``, which
/// this holds and which pins them under test on its own.
///
/// Both collaborators are injected rather than reached for as globals, so the
/// composition this type exists to perform is testable: that a completed visit
/// produces exactly one event, that the duration is the tracker's span, and
/// that `is_playing` describes the end of the visit.
///
/// `isPlaying` is a closure rather than a value because the answer is only
/// meaningful at the instant the visit closes. Note the ordering it observes
/// in the app: `WXYCApp` hands `AudioPlayerController` its own background
/// notification before routing the phase here, so a visit the listener ended
/// by pausing reads as not playing — the same value its sibling
/// `app_entered_background` reports for the same edge.
@MainActor
public final class ForegroundSessionReporter {

    private var tracker = ForegroundSessionTracker()
    private let analytics: any AnalyticsService
    private let isPlaying: () -> Bool

    /// Creates a reporter.
    ///
    /// - Parameters:
    ///   - analytics: Where completed visits are captured.
    ///   - isPlaying: Whether audio is playing, evaluated as each visit ends.
    public init(analytics: any AnalyticsService, isPlaying: @escaping () -> Bool) {
        self.analytics = analytics
        self.isPlaying = isPlaying
    }

    /// Records one visibility transition, capturing a `foreground_session` if
    /// it ended a visit.
    ///
    /// - Parameters:
    ///   - visibility: What the phase being entered says about visibility.
    ///   - instant: When the transition happened. Defaults to now; tests pass
    ///     explicit instants so no assertion depends on wall-clock timing.
    public func record(
        _ visibility: ForegroundVisibility,
        at instant: ContinuousClock.Instant = ContinuousClock.now
    ) {
        guard let session = tracker.record(visibility, at: instant) else { return }

        analytics.capture(ForegroundSession(
            durationSeconds: session.timeInterval,
            isPlaying: isPlaying()
        ))
    }
}
