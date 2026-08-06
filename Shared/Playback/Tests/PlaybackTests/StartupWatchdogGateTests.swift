//
//  StartupWatchdogGateTests.swift
//  Playback
//
//  Pins the contract `StartupWatchdogGate` has to honour to be a faithful
//  stand-in for the `Task.sleep` behind a startup watchdog's deadline: FIFO
//  release order, cancellation retiring a superseded arm, releases banking
//  rather than vanishing, and a bounded `waitForArm`. Every one of these is
//  load-bearing for the suites that inject the gate — a gate that got any of
//  them wrong would let those suites pass while driving zero watchdog fires.
//  See issue #787.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Synchronization
import PlaybackTestUtilities

@Suite("Startup Watchdog Gate")
@MainActor
struct StartupWatchdogGateTests {
    @Test("release() resumes arms in the order they were installed")
    func releaseIsFirstInFirstOut() async throws {
        let gate = StartupWatchdogGate()
        let completions = Mutex<[Int]>([])

        let first = Task { @MainActor in
            try await gate.sleep(for: .seconds(1))
            completions.withLock { $0.append(1) }
        }
        try await gate.waitForArm()

        let second = Task { @MainActor in
            try await gate.sleep(for: .seconds(2))
            completions.withLock { $0.append(2) }
        }
        await pollUntil { gate.pendingArmCount == 2 }
        #expect(gate.pendingArmCount == 2)

        gate.release()
        try await first.value
        #expect(completions.withLock { $0 } == [1])

        gate.release()
        try await second.value
        #expect(completions.withLock { $0 } == [1, 2])
        #expect(gate.fireCount == 2)
    }

    /// The regression that makes a gated suite lie. Both watchdogs re-arm by
    /// cancelling the prior arm and installing a fresh one; if a cancelled arm
    /// stayed suspended it would still be first in line, so the next release
    /// would resume *it* — a silent no-op behind its own `Task.isCancelled`
    /// guard — while the live arm stayed parked.
    @Test("A cancelled arm retires instead of lingering to absorb a later release")
    func cancellationRetiresTheArm() async throws {
        let gate = StartupWatchdogGate()

        let superseded = Task { @MainActor () -> Bool in
            do {
                try await gate.sleep(for: .seconds(1))
                return false
            } catch {
                return true
            }
        }
        try await gate.waitForArm()

        superseded.cancel()
        #expect(await superseded.value, "A cancelled arm must throw, not stay suspended")
        await pollUntil { gate.pendingArmCount == 0 }
        #expect(gate.pendingArmCount == 0, "A cancelled arm must not stay parked on the gate")

        let live = Task { @MainActor in
            try await gate.sleep(for: .seconds(1))
        }
        try await gate.waitForArm()

        gate.release()
        try await live.value
        #expect(gate.fireCount == 1, "The release must reach the live arm, not the retired one")
    }

    @Test("A release with nothing armed is banked for the next arm")
    func releaseBeforeArmIsBanked() async throws {
        let gate = StartupWatchdogGate()

        gate.release()
        #expect(gate.fireCount == 0, "Nothing has armed yet, so nothing has fired")

        // On a gate that dropped the early release, this would suspend forever.
        try await gate.sleep(for: .seconds(1))
        #expect(gate.fireCount == 1)
        #expect(gate.pendingArmCount == 0)
    }

    @Test("waitForArm throws rather than hanging when nothing arms")
    func waitForArmTimesOut() async throws {
        let gate = StartupWatchdogGate()

        await #expect(throws: StartupWatchdogGate.ArmTimeout.self) {
            try await gate.waitForArm(timeout: .milliseconds(50))
        }
    }

    @Test("releaseAll drains every parked arm without counting as a fire")
    func releaseAllDrainsWithoutFiring() async throws {
        let gate = StartupWatchdogGate()

        let first = Task { @MainActor in try await gate.sleep(for: .seconds(1)) }
        try await gate.waitForArm()
        let second = Task { @MainActor in try await gate.sleep(for: .seconds(2)) }
        await pollUntil { gate.pendingArmCount == 2 }

        gate.releaseAll()
        try await first.value
        try await second.value

        #expect(gate.pendingArmCount == 0)
        #expect(gate.fireCount == 0, "A teardown drain is not a watchdog fire")
    }

    @Test("The gate records the deadline every arm asked for, and ignores it")
    func recordsRequestedDurations() async throws {
        let gate = StartupWatchdogGate()

        gate.release()
        gate.release()
        // Neither call waits out its nominal deadline; both return on a banked
        // release. The durations survive for a test to assert on.
        try await gate.sleep(for: .seconds(12))
        try await gate.sleep(for: .milliseconds(300))

        #expect(gate.requestedDurations == [.seconds(12), .milliseconds(300)])
    }
}
