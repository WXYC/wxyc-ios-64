//
//  Timer.swift
//  Core
//
//  Simple elapsed time measurement utility for performance logging.
//
//  Created by Jake Bromberg on 03/02/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// Simple elapsed-time measurement utility for performance logging and latency
/// metrics.
///
/// Backed by the monotonic `ContinuousClock` rather than a `Date` delta, so a
/// wall-clock adjustment while a measurement is in flight — an NTP step, a DST
/// change, a manual clock change — can never make a reported duration jump or
/// go negative. This matters for values that feed a distribution (e.g.
/// `time_to_first_audio`), where a single negative sample is meaningless.
public struct Timer: Sendable {
    public static func start() -> Timer {
        return Timer()
    }

    public func duration() -> TimeInterval {
        let elapsed = start.duration(to: ContinuousClock().now)
        return TimeInterval(elapsed.components.seconds)
            + TimeInterval(elapsed.components.attoseconds) / 1e18
    }

    let start: ContinuousClock.Instant = ContinuousClock().now

    private init() { }
}
