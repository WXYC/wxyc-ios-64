//
//  DurationTimeIntervalTests.swift
//  Core
//
//  Pins the `Duration` -> `TimeInterval` bridge, including the fractional part
//  that a `components.seconds`-only conversion silently drops.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Core

@Suite("Duration as TimeInterval")
struct DurationTimeIntervalTests {

    @Test(
        "Whole and fractional seconds both survive the conversion",
        arguments: [
            (Duration.zero, 0.0),
            (Duration.seconds(12), 12.0),
            // The case a `TimeInterval(components.seconds)` conversion drops
            // entirely: attoseconds carry everything below a second, and most
            // foreground visits are seconds long.
            (Duration.milliseconds(1500), 1.5),
            (Duration.milliseconds(250), 0.25),
            (Duration.seconds(3600) + .milliseconds(500), 3600.5),
        ]
    )
    func durationConvertsToSeconds(duration: Duration, expected: TimeInterval) {
        #expect(duration.timeInterval == expected)
    }

    @Test("A negative duration stays negative rather than wrapping")
    func negativeDurationConverts() {
        // Not reachable from a monotonic clock, but a conversion that silently
        // flipped the sign would hide the bug that produced it.
        #expect((Duration.seconds(-3)).timeInterval == -3.0)
    }
}
