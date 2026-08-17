//
//  RunOnceGateTests.swift
//  MusicShareKit
//
//  Tests for RunOnceGate, the primitive backing MusicShareKit.configure(_:)'s
//  once-per-process guard (#956). Exercises fresh, per-test instances so
//  these assertions are immune to the cross-suite races that
//  MusicShareKit's shared globals are already documented to tolerate
//  (see DeviceFingerprintConfigurationTests.makeConfiguration).
//
//  Created by Jake Bromberg on 08/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Synchronization
import Testing
@testable import MusicShareKit

@Suite("RunOnceGate Tests")
struct RunOnceGateTests {

    @Test("runOnce executes its body on the first call")
    func firstCallRuns() {
        let gate = RunOnceGate()
        var callCount = 0

        gate.runOnce { callCount += 1 }

        #expect(callCount == 1)
    }

    @Test("runOnce does not execute its body on a second call")
    func secondCallIsANoOp() {
        let gate = RunOnceGate()
        var callCount = 0

        gate.runOnce { callCount += 1 }
        gate.runOnce { callCount += 1 }

        #expect(callCount == 1)
    }

    @Test("hasRun reports whether the gate has been consumed")
    func hasRunTracksConsumption() {
        let gate = RunOnceGate()
        #expect(gate.hasRun == false)

        gate.runOnce { }

        #expect(gate.hasRun)
    }

    @Test("runOnce does not execute its body across many repeated calls")
    func repeatedCallsStayAtOne() {
        let gate = RunOnceGate()
        var callCount = 0

        for _ in 0..<5 {
            gate.runOnce { callCount += 1 }
        }

        #expect(callCount == 1)
    }

    /// `MusicShareKit.configure(_:)` is `public` and `nonisolated`, so a
    /// future caller is not confined to the main thread. An unsynchronized
    /// check-then-set would let two callers both pass the guard and both
    /// rebuild `_authService` — the exact failure #956 closes.
    @Test("Concurrent callers still run the body exactly once")
    func concurrentCallersRunBodyOnce() async {
        let gate = RunOnceGate()
        let callCount = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    gate.runOnce { callCount.increment() }
                }
            }
        }

        #expect(callCount.value == 1)
    }
}

/// A `Sendable` tally the concurrency test's child tasks can share.
///
/// `Mutex` is `~Copyable`, so a bare `Mutex<Int>` local can't be captured by
/// the `sending` closure `addTask` takes; boxing it in a final class gives
/// the tasks a reference to share instead.
private final class Counter: Sendable {
    private let storage = Mutex(0)

    var value: Int { storage.withLock { $0 } }

    func increment() {
        storage.withLock { $0 += 1 }
    }
}
