//
//  ExceptionGateTests.swift
//  Analytics
//
//  Verifies the 60-second dedupe and the per-launch token bucket that cap
//  handled-error `$exception` sends, using a manual clock instead of sleeping.
//
//  Created by Jake Bromberg on 10/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics

/// A hand-advanced monotonic clock for driving `ExceptionGate` deterministically.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: Duration = .zero

    var now: Duration {
        lock.withLock { elapsed }
    }

    func advance(by duration: Duration) {
        lock.withLock { elapsed += duration }
    }
}

@Suite("ExceptionGate")
struct ExceptionGateTests {

    private func makeGate(clock: ManualClock) -> ExceptionGate {
        ExceptionGate(now: { clock.now })
    }

    @Test("A repeat inside 60 seconds is dropped and costs no token")
    func repeatInsideWindowIsDroppedWithoutSpendingAToken() {
        let clock = ManualClock()
        let gate = makeGate(clock: clock)

        #expect(gate.admit(key: "a"))
        for _ in 0..<50 {
            clock.advance(by: .seconds(1))
            #expect(!gate.admit(key: "a"))
        }

        // 19 tokens remain, so 19 distinct keys fit after the 50 suppressed repeats.
        for index in 0..<19 {
            #expect(gate.admit(key: "distinct-\(index)"))
        }
        #expect(!gate.admit(key: "one-too-many"))
    }

    @Test("The same key is admitted again once 60 seconds have passed")
    func sameKeyAfterWindowIsAdmitted() {
        let clock = ManualClock()
        let gate = makeGate(clock: clock)

        #expect(gate.admit(key: "a"))
        clock.advance(by: .seconds(59))
        #expect(!gate.admit(key: "a"))
        clock.advance(by: .seconds(1))
        #expect(gate.admit(key: "a"))
    }

    @Test("Twenty distinct errors are admitted and the twenty-first is dropped")
    func burstIsTwenty() {
        let gate = makeGate(clock: ManualClock())

        for index in 0..<20 {
            #expect(gate.admit(key: "error-\(index)"))
        }
        #expect(!gate.admit(key: "error-20"))
    }

    @Test("A token comes back after the 30-minute refill interval")
    func tokenRefillsEveryThirtyMinutes() {
        let clock = ManualClock()
        let gate = makeGate(clock: clock)
        for index in 0..<20 {
            _ = gate.admit(key: "error-\(index)")
        }

        clock.advance(by: .seconds(1799))
        #expect(!gate.admit(key: "late"))
        clock.advance(by: .seconds(1))
        #expect(gate.admit(key: "late"))
        #expect(!gate.admit(key: "later"))
    }

    @Test("A key dropped for want of a token is not remembered as admitted")
    func droppedKeyIsNotRecorded() {
        let clock = ManualClock()
        let gate = makeGate(clock: clock)
        for index in 0..<20 {
            _ = gate.admit(key: "error-\(index)")
        }

        #expect(!gate.admit(key: "starved"))
        clock.advance(by: .seconds(1800))
        #expect(gate.admit(key: "starved"))
    }

    @Test("Every drop is counted")
    func dropsAreCounted() {
        let gate = makeGate(clock: ManualClock())

        _ = gate.admit(key: "a")
        _ = gate.admit(key: "a")
        _ = gate.admit(key: "a")

        #expect(gate.droppedCount == 2)
    }

    @Test("The dedupe table stays bounded at 1,000 keys")
    func dedupeTableIsBounded() {
        let clock = ManualClock()
        let gate = ExceptionGate(burst: 5_000, now: { clock.now })

        for index in 0..<1_500 {
            clock.advance(by: .milliseconds(1))
            #expect(gate.admit(key: "error-\(index)"))
        }

        #expect(gate.dedupeKeyCount == 1_000)
        // The oldest key was evicted, so it is admitted again; the newest is still deduped.
        #expect(gate.admit(key: "error-0"))
        #expect(!gate.admit(key: "error-1499"))
    }
}
