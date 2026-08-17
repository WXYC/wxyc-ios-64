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

import Testing
@testable import MusicShareKit

@Suite("RunOnceGate Tests")
struct RunOnceGateTests {

    @Test("runOnce executes its body exactly once no matter how often it is called", arguments: [1, 2, 5])
    func runOnceExecutesBodyExactlyOnce(callsMade: Int) {
        let gate = RunOnceGate()
        var callCount = 0

        for _ in 0..<callsMade {
            gate.runOnce { callCount += 1 }
        }

        #expect(callCount == 1)
    }

    @Test("hasRun reports whether the gate has been consumed")
    func hasRunTracksConsumption() {
        let gate = RunOnceGate()
        #expect(gate.hasRun == false)

        gate.runOnce { }

        #expect(gate.hasRun)
    }

    /// `MusicShareKit.configure(_:)` is `public` and `nonisolated`, so a
    /// future caller is not confined to the main thread. An unsynchronized
    /// check-then-set would let two callers both pass the guard and both
    /// rebuild `_authService` — the exact failure #956 closes.
    @Test("Concurrent callers still run the body exactly once")
    func concurrentCallersRunBodyOnce() async {
        let gate = RunOnceGate()

        // Each child task reports whether IT was the winner, so the tally
        // needs no shared mutable state: `runOnce`'s `body` is non-escaping,
        // so mutating the task-local `didRun` is legal.
        let runs = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    var didRun = false
                    gate.runOnce { didRun = true }
                    return didRun
                }
            }
            return await group.reduce(into: 0) { $0 += $1 ? 1 : 0 }
        }

        #expect(runs == 1)
    }
}
