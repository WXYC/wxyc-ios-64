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
