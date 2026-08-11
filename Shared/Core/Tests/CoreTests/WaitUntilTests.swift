//
//  WaitUntilTests.swift
//  CoreTests
//
//  Tests for the canonical `waitUntil` polling helper (#766): it must return
//  `true` as soon as the condition holds, and `false` — never silently pass —
//  when the condition never becomes true before the deadline.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import CoreTesting

@Suite("waitUntil Tests")
struct WaitUntilTests {

    @Test("Returns true once the condition becomes true")
    func returnsTrueWhenConditionBecomesTrue() async {
        var callCount = 0
        let succeeded = await waitUntil(timeout: .seconds(1)) {
            callCount += 1
            return callCount >= 3
        }
        #expect(succeeded)
        #expect(callCount >= 3)
    }

    @Test("Returns true immediately when the condition already holds")
    func returnsTrueImmediatelyWhenAlreadyTrue() async {
        let succeeded = await waitUntil(timeout: .seconds(1)) {
            true
        }
        #expect(succeeded)
    }

    @Test("Returns false — rather than swallowing the timeout — when the condition never holds")
    func returnsFalseOnTimeout() async {
        let succeeded = await waitUntil(timeout: .milliseconds(50)) {
            false
        }
        #expect(succeeded == false)
    }

    @Test("A cancelled wait gives up immediately instead of spinning out its deadline")
    func cancellationEndsTheWaitEarly() async {
        // Swift Testing's `.timeLimit` enforces itself by cancelling the task.
        // A `Task.yield()` spin neither throws on cancellation nor checks
        // `Task.isCancelled`, so under a spin this helper would pin a
        // cooperative thread for the full ten seconds and the time limit would
        // be decorative. Sleeping between polls is what makes the wait
        // cancellable — this test is the guard on that (#766, mechanic per #807).
        let start = ContinuousClock.now
        let task = Task { await waitUntil(timeout: .seconds(10)) { false } }
        task.cancel()
        let succeeded = await task.value
        let elapsed = ContinuousClock.now - start

        #expect(succeeded == false)
        #expect(elapsed < .seconds(2), "Cancelled wait took \(elapsed); it should abandon the deadline, not run it out")
    }

    @Test("Supports async conditions that need to await other work")
    func supportsAsyncConditions() async {
        actor Counter {
            private(set) var value = 0
            func increment() { value += 1 }
        }
        let counter = Counter()
        let succeeded = await waitUntil(timeout: .seconds(1)) {
            await counter.increment()
            return await counter.value >= 2
        }
        #expect(succeeded)
    }
}
