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

    private final class LogSink: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []

        var messages: [String] {
            lock.withLock { stored }
        }

        func record(_ message: String) {
            lock.withLock { stored.append(message) }
        }
    }

    @Test("Drops are logged at most once every 15 minutes, with the count accumulated since the last log")
    func dropLogIsRateLimited() {
        let clock = ManualClock()
        let sink = LogSink()
        let gate = ExceptionGate(now: { clock.now }, log: { sink.record($0) })

        #expect(gate.admit(key: "a"))
        for _ in 0..<5 {
            #expect(!gate.admit(key: "a"))
        }
        #expect(sink.messages.count == 1)
        #expect(sink.messages[0].contains("Dropped 1 "))

        // The dedupe window has lapsed by 14:59, so "a" is admitted afresh; the drop that
        // follows at 15:00 is the first one past the log interval.
        clock.advance(by: .seconds(15 * 60 - 1))
        #expect(gate.admit(key: "a"))
        clock.advance(by: .seconds(1))
        #expect(!gate.admit(key: "a"))
        #expect(sink.messages.count == 2)
        #expect(sink.messages[1].contains("Dropped 5 "))
        #expect(sink.messages[1].contains("(6 since launch)"))
    }

    @Test("A drop 15 minutes minus a second after the last warning is not logged")
    func dropLogHoldsUntilFifteenMinutes() {
        let clock = ManualClock()
        let sink = LogSink()
        let gate = ExceptionGate(now: { clock.now }, log: { sink.record($0) })

        #expect(gate.admit(key: "a"))
        #expect(!gate.admit(key: "a"))
        #expect(sink.messages.count == 1)

        // The dedupe window has lapsed by then, so "a" is admitted afresh and its repeats drop.
        clock.advance(by: .seconds(15 * 60 - 2))
        #expect(gate.admit(key: "a"))
        clock.advance(by: .seconds(1))
        #expect(!gate.admit(key: "a"))
        #expect(sink.messages.count == 1)
        clock.advance(by: .seconds(1))
        #expect(!gate.admit(key: "a"))
        #expect(sink.messages.count == 2)
    }

    /// One row of the client gate scenario table in wiki `patterns/error-tracking.md` §5.
    struct ScenarioStep: Sendable, CustomTestStringConvertible {
        let step: String
        let clockSeconds: Int
        let keys: [String]
        let admitted: Bool
        /// The drop count the admitted event carries; zero means the property is absent.
        let droppedSinceLast: Int
        let warns: Bool

        var testDescription: String { step }
    }

    private static func keys(_ range: ClosedRange<Int>) -> [String] {
        range.map { "k\($0)" }
    }

    static let scenarios: [(name: String, steps: [ScenarioStep])] = [
        ("A: 20/21 boundary, refill", [
            ScenarioStep(step: "A1", clockSeconds: 0, keys: keys(1...20), admitted: true, droppedSinceLast: 0, warns: false),
            ScenarioStep(step: "A2", clockSeconds: 0, keys: ["k21"], admitted: false, droppedSinceLast: 0, warns: true),
            ScenarioStep(step: "A3", clockSeconds: 29 * 60 + 59, keys: ["k22"], admitted: false, droppedSinceLast: 0, warns: true),
            ScenarioStep(step: "A4", clockSeconds: 30 * 60, keys: ["k23"], admitted: true, droppedSinceLast: 2, warns: false),
            ScenarioStep(step: "A5", clockSeconds: 30 * 60, keys: ["k24"], admitted: false, droppedSinceLast: 0, warns: false),
            ScenarioStep(step: "A6", clockSeconds: 60 * 60, keys: ["k25"], admitted: true, droppedSinceLast: 1, warns: false),
            ScenarioStep(step: "A7", clockSeconds: 90 * 60, keys: ["k26"], admitted: true, droppedSinceLast: 0, warns: false),
            ScenarioStep(step: "A7 bucket empty", clockSeconds: 90 * 60, keys: ["k27"], admitted: false, droppedSinceLast: 0, warns: true),
        ]),
        ("C: refill capped at 20", [
            ScenarioStep(step: "C1", clockSeconds: 0, keys: ["k1"], admitted: true, droppedSinceLast: 0, warns: false),
            ScenarioStep(step: "C2", clockSeconds: 600 * 60, keys: ["k2"], admitted: true, droppedSinceLast: 0, warns: false),
            // 19 tokens left after C2, and no more.
            ScenarioStep(step: "C2 tokens left", clockSeconds: 600 * 60, keys: keys(3...21), admitted: true, droppedSinceLast: 0, warns: false),
            ScenarioStep(step: "C2 bucket empty", clockSeconds: 600 * 60, keys: ["k22"], admitted: false, droppedSinceLast: 0, warns: true),
        ]),
        ("D: a full bucket restarts the refill clock", [
            ScenarioStep(step: "D1", clockSeconds: 29 * 60, keys: keys(1...20), admitted: true, droppedSinceLast: 0, warns: false),
            ScenarioStep(step: "D2", clockSeconds: 30 * 60, keys: ["k21"], admitted: false, droppedSinceLast: 0, warns: true),
            ScenarioStep(step: "D3", clockSeconds: 58 * 60 + 59, keys: ["k22"], admitted: false, droppedSinceLast: 0, warns: true),
            ScenarioStep(step: "D4", clockSeconds: 59 * 60, keys: ["k23"], admitted: true, droppedSinceLast: 2, warns: false),
            ScenarioStep(step: "D4 tokens left", clockSeconds: 59 * 60, keys: ["k24"], admitted: false, droppedSinceLast: 0, warns: false),
        ]),
    ]

    @Test("Client gate scenario table rows match the wiki", arguments: scenarios.map(\.name))
    func scenarioTable(name: String) {
        let steps = Self.scenarios.first { $0.name == name }!.steps
        let clock = ManualClock()
        let sink = LogSink()
        let gate = ExceptionGate(now: { clock.now }, log: { sink.record($0) })

        for row in steps {
            clock.advance(by: .seconds(row.clockSeconds) - clock.now)
            let warningsBefore = sink.messages.count
            for (index, key) in row.keys.enumerated() {
                let result = gate.admitReportingDrops(key: key)
                if row.admitted {
                    let expected = index == 0 ? row.droppedSinceLast : 0
                    #expect(result == expected, "\(row.step) \(key)")
                } else {
                    #expect(result == nil, "\(row.step) \(key)")
                }
            }
            #expect((sink.messages.count > warningsBefore) == row.warns, "\(row.step) warning")
        }
    }

    @Test("dropped_since_last is the drop count on the next admit, then resets")
    func droppedSinceLastIsReportedOnceThenReset() {
        let clock = ManualClock()
        let gate = ExceptionGate(now: { clock.now }, log: { _ in })

        #expect(gate.admitReportingDrops(key: "a") == 0)
        for _ in 0..<3 {
            #expect(gate.admitReportingDrops(key: "a") == nil)
        }
        clock.advance(by: .seconds(60))
        #expect(gate.admitReportingDrops(key: "a") == 3)
        clock.advance(by: .seconds(60))
        #expect(gate.admitReportingDrops(key: "a") == 0)
    }

    @Test("Calls every 3 minutes after a drain still grant the token due at exactly 30:00")
    func tokenDueAtThirtyMinutesIsGrantedDespiteInterveningCalls() {
        let clock = ManualClock()
        let gate = makeGate(clock: clock)
        for index in 0..<20 {
            _ = gate.admit(key: "error-\(index)")
        }

        for _ in 0..<9 {
            clock.advance(by: .seconds(180))
            #expect(!gate.admit(key: "late"))
        }
        clock.advance(by: .seconds(180))
        #expect(gate.admit(key: "late"))
    }

    @Test("One-second steps through 30 minutes grant the token at exactly 30:00")
    func tokenArrivesExactlyAtThirtyMinutesWithOneSecondSteps() {
        let clock = ManualClock()
        let gate = makeGate(clock: clock)
        for index in 0..<20 {
            _ = gate.admit(key: "error-\(index)")
        }

        for second in 1..<1800 {
            clock.advance(by: .seconds(1))
            #expect(!gate.admit(key: "late-\(second)"), "granted early at \(second)s")
        }
        clock.advance(by: .seconds(1))
        #expect(gate.admit(key: "due"))
    }

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
