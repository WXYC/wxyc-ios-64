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

    @Test("runOnce does not execute its body across many repeated calls")
    func repeatedCallsStayAtOne() {
        let gate = RunOnceGate()
        var callCount = 0

        for _ in 0..<5 {
            gate.runOnce { callCount += 1 }
        }

        #expect(callCount == 1)
    }
}
