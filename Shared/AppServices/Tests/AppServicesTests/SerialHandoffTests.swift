//
//  SerialHandoffTests.swift
//  AppServices
//
//  Pins the ordering guarantee that `SerialHandoff` exists to provide: work
//  reaches its destination actor in the order it was enqueued, even when an
//  earlier item suspends and a later one is ready to run. Two bare `Task {}`s
//  have no relative ordering, which let a `.background`/`.active` pair invert
//  on the way to `PlaylistService` and latch `isForegrounded = false` while the
//  app was on screen — leaving the `live-fs-topic` SSE subscription down for
//  the rest of the session. See WXYC/wxyc-ios-64#269 for the subscription this
//  protects.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import AppServices

/// Records the order in which enqueued work actually ran.
private actor OrderRecorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// A gate that also reports when someone has arrived at it.
///
/// `waitForArrival()` is what makes these tests deterministic rather than
/// timing-dependent: it returns only once the first work item is genuinely
/// parked mid-flight, so the assertions that follow describe a known schedule
/// instead of racing one.
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalCount = 0
    private var isOpen = false

    /// Parks the caller until `open()`, announcing its arrival first.
    func wait() async {
        arrivalCount += 1
        for waiter in arrivalWaiters {
            waiter.resume()
        }
        arrivalWaiters.removeAll()

        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Returns once at least one caller has reached `wait()`.
    func waitForArrival() async {
        guard arrivalCount == 0 else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

@MainActor
@Suite("Serial handoff")
struct SerialHandoffTests {

    @Test("Later work does not begin until earlier work has finished")
    func laterWorkWaitsForEarlier() async {
        let recorder = OrderRecorder()
        let gate = Gate()
        let handoff = SerialHandoff()

        handoff.enqueue {
            await recorder.record("first-start")
            await gate.wait()
            await recorder.record("first-end")
        }
        handoff.enqueue {
            await recorder.record("second")
        }

        // Deterministic: returns only once the first item is parked inside the
        // gate. An unserialized dispatch leaves the second item runnable for
        // the whole of that window.
        await gate.waitForArrival()
        #expect(await recorder.entries == ["first-start"])

        await gate.open()
        await handoff.drain()

        #expect(await recorder.entries == ["first-start", "first-end", "second"])
    }

    @Test("A rapid transition pair settles on the value enqueued last")
    func lastEnqueuedValueWins() async {
        // The live-fs failure in miniature: `false` then `true`, dispatched
        // back to back the way a `.background`/`.active` pair arrives. Arrival
        // order is the only thing that decides the final state, so preserving
        // it is what keeps the subscription up.
        let recorder = OrderRecorder()
        let handoff = SerialHandoff()

        for value in [false, true, false, true] {
            handoff.enqueue {
                await recorder.record("\(value)")
            }
        }

        await handoff.drain()

        #expect(await recorder.entries == ["false", "true", "false", "true"])
        #expect(await recorder.entries.last == "true")
    }

    @Test("Draining an idle handoff returns immediately")
    func drainingIdleHandoffIsANoOp() async {
        let handoff = SerialHandoff()
        await handoff.drain()
    }
}
