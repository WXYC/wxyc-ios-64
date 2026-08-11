//
//  PollUntilStableTests.swift
//  Playback
//
//  Pins the contract `pollUntilStable` has to honour to be a trustworthy
//  quiescence wait: it must not report a still-moving pipeline as settled, it
//  must return once the pipeline genuinely settles, and — the load-bearing one
//  — it must require consecutive *observations* rather than elapsed time alone.
//  A purely time-based dwell would resume from any scheduling pause longer than
//  the dwell, see the single unchanged value a frozen producer guarantees, and
//  call a mid-drain pipeline quiescent. `stallTolerantTimeout` documents this
//  process being descheduled for ~10.5s at a stretch, so that is a measured
//  hazard here, not a hypothetical one. See issue #807.
//
//  Created by Jake Bromberg on 08/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import PlaybackTestUtilities

@Suite("Poll Until Stable")
@MainActor
struct PollUntilStableTests {
    @Test("Elapsed time alone does not count as quiescence")
    func requiresConsecutiveObservations() async {
        var observations = 0

        // The dwell is shorter than a single poll interval and the value never
        // moves, so a dwell-only implementation would satisfy its deadline on
        // the very first observation after the first sleep and return with
        // `observations == 2`. Anything materially above that is the
        // consecutive-sample requirement doing the work — which is exactly the
        // part a descheduled process cannot fake, because a pause of any length
        // yields one observation, not ten.
        await pollUntilStable(dwell: .milliseconds(1), timeout: .seconds(5)) {
            observations += 1
            return 7
        }

        #expect(observations >= 11,
                "Quiescence must cost real scheduled time, not just wall-clock time; got \(observations) observations")
    }

    @Test("A value that keeps moving is never reported as settled")
    func neverSettlesWhileChanging() async {
        var value = 0
        let clock = ContinuousClock()
        let start = clock.now

        // Changes on every observation, so quiescence is never reachable and
        // the call must run out its (deliberately short) timeout instead of
        // returning early.
        await pollUntilStable(dwell: .milliseconds(20), timeout: .milliseconds(300)) {
            value += 1
            return value
        }

        #expect(clock.now - start >= .milliseconds(250),
                "A continuously changing sample must hold the wait open until the timeout")
    }

    @Test("Returns once the sampled value settles")
    func returnsOnceSettled() async {
        var remainingChanges = 5
        var value = 0
        let clock = ContinuousClock()
        let start = clock.now

        await pollUntilStable(dwell: .milliseconds(20), timeout: .seconds(5)) {
            if remainingChanges > 0 {
                remainingChanges -= 1
                value += 1
            }
            return value
        }

        #expect(remainingChanges == 0, "The wait must outlast the changes it was watching")
        #expect(clock.now - start < .seconds(5), "Settling must return well before the timeout")
    }
}
