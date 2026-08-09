//
//  SerialHandoffTests.swift
//  Core
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
//  Both tests park the first item so every later one is runnable during the
//  wait. Only `laterWorkWaitsForEarlier` fails deterministically against an
//  unserialized implementation, though — see the note on the other test.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Core

@MainActor
@Suite("Serial handoff")
struct SerialHandoffTests {

    @Test("Later work does not begin until earlier work has finished", .timeLimit(.minutes(1)))
    func laterWorkWaitsForEarlier() async {
        let recorder = OrderRecorder()
        let arrived = OneShot()
        let release = OneShot()
        let handoff = SerialHandoff()

        handoff.enqueue {
            await recorder.record("first-start")
            await arrived.signal()
            await release.wait()
            await recorder.record("first-end")
        }
        handoff.enqueue {
            await recorder.record("second")
        }

        // Deterministic: returns only once the first item is parked mid-flight.
        await arrived.wait()
        #expect(await recorder.entries == ["first-start"])

        await release.signal()
        await handoff.drain()

        #expect(await recorder.entries == ["first-start", "first-end", "second"])
    }

    @Test("A rapid transition burst settles on the value enqueued last", .timeLimit(.minutes(1)))
    func lastEnqueuedValueWins() async {
        // The live-fs failure in miniature: alternating states dispatched back
        // to back the way a `.background`/`.active` pair arrives. Arrival order
        // is the only thing that decides the final state, so preserving it is
        // what keeps the subscription up.
        //
        // This is the scenario, not the guard. Parking the first item leaves
        // the other three runnable for the whole wait, so an unserialized
        // dispatch usually overtakes and fails here — but only usually: nothing
        // compels the runtime to actually schedule them while item 0 is parked,
        // and if it doesn't, they land in order by luck and this passes anyway.
        // `laterWorkWaitsForEarlier` is the test that fails deterministically;
        // keep this one for the shape of the real burst, not to rely on it.
        let recorder = OrderRecorder()
        let arrived = OneShot()
        let release = OneShot()
        let handoff = SerialHandoff()

        for (index, value) in [false, true, false, true].enumerated() {
            handoff.enqueue {
                if index == 0 {
                    await arrived.signal()
                    await release.wait()
                }
                await recorder.record("\(value)")
            }
        }

        await arrived.wait()
        await release.signal()
        await handoff.drain()

        #expect(await recorder.entries == ["false", "true", "false", "true"])
        #expect(await recorder.entries.last == "true")
    }
}

/// Records the order in which enqueued work actually ran.
private actor OrderRecorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// A one-shot signal: `wait()` returns once `signal()` has been called, whether
/// that happened before or after the wait began.
///
/// Two of these compose into the schedule these tests need — one to learn that
/// an item has parked, one to let it go — which keeps each signal independent
/// rather than fusing arrival and release into a single object.
private actor OneShot {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignalled = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
