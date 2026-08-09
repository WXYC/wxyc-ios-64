//
//  LatestValueRelayTests.swift
//  Core
//
//  Pins the three properties `LatestValueRelay` exists to provide: values reach
//  the handler in send order, a burst that piles up behind a busy handler
//  collapses to its final value, and construction alone is enough to start
//  delivering — there is no start step a caller can forget.
//
//  The ordering property is the one with a bug behind it. Two bare `Task {}`s
//  have no relative ordering, which let a `.background`/`.active` pair invert on
//  the way to `PlaylistService` and latch `isForegrounded = false` while the app
//  was on screen, leaving the `live-fs-topic` SSE subscription down for the rest
//  of the session. See WXYC/wxyc-ios-64#269 for the subscription this protects.
//
//  Every test parks the handler on its first value, so the relay's buffer is the
//  only thing that can hold anything sent afterwards. That makes each assertion
//  deterministic rather than a race the scheduler usually loses.
//
//  Created by Jake Bromberg on 08/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Core

@Suite("Latest value relay")
struct LatestValueRelayTests {

    @Test("Values reach the handler in the order they were sent", .timeLimit(.minutes(1)))
    func preservesSendOrder() async {
        let recorder = Recorder()
        let release = OneShot()

        // Recording both ends of the handler is what makes the failure legible:
        // a per-value `Task {}` doesn't reorder the *sends*, it overlaps the
        // *handlers*, and only an exit marker can show the second one running
        // inside the first.
        let relay = LatestValueRelay<String> { value in
            await recorder.record("\(value)-start")
            if value == "first" {
                await release.wait()
            }
            await recorder.record("\(value)-end")
        }

        relay.send("first")
        // Returns only once the handler is inside `handle("first")`, so nothing
        // below can be dequeued until `release` is signalled.
        await recorder.wait(untilCount: 1)

        relay.send("second")
        await settle()
        #expect(await recorder.entries == ["first-start"])

        await release.signal()
        await recorder.wait(untilCount: 4)

        #expect(await recorder.entries == ["first-start", "first-end", "second-start", "second-end"])
    }

    @Test("A burst behind a busy handler collapses to its final value", .timeLimit(.minutes(1)))
    func burstCollapsesToFinalValue() async {
        // The live-fs failure in miniature: alternating states pushed back to
        // back the way a `.background`/`.active` pair arrives. Only the last one
        // describes the world, and the intermediate ones would each cost an SSE
        // teardown and reconnect on the way through.
        let recorder = Recorder()
        let release = OneShot()

        let relay = LatestValueRelay<Bool> { value in
            await recorder.record("\(value)")
            if await recorder.entries.count == 1 {
                await release.wait()
            }
        }

        relay.send(false)
        await recorder.wait(untilCount: 1)

        // All three land in a one-slot buffer while the handler is parked, so
        // the middle two are superseded before anyone can observe them.
        relay.send(true)
        relay.send(false)
        relay.send(true)

        await release.signal()
        await recorder.wait(untilCount: 2)
        await settle()

        // Exactly two deliveries, ever. A mechanism that ran every value would
        // land four here, which is the assertion doing the work — the prefix
        // alone would match either way.
        #expect(await recorder.entries == ["false", "true"])
    }

    @Test("Construction is enough to start delivering", .timeLimit(.minutes(1)))
    func deliversWithoutAnExplicitStart() async {
        // A relay whose consumer has to be started separately drops everything
        // sent before someone remembers to start it. For the foreground state
        // that means `PlaylistService` never learns the app is on screen and the
        // subscription never opens at all — a worse failure than the inverted
        // pair this type replaced.
        let recorder = Recorder()

        let relay = LatestValueRelay<String> { await recorder.record($0) }
        relay.send("only")

        await recorder.wait(untilCount: 1)

        #expect(await recorder.entries == ["only"])
    }
}

/// Gives any task that is already runnable a generous chance to run before the
/// caller asserts that it didn't.
///
/// Both negative assertions here — "the second value has not been delivered yet"
/// and "nothing further was delivered" — are claims about work that must *not*
/// have happened, which no amount of awaiting can establish outright. A wrong
/// implementation dispatches a task per value, and those tasks are runnable from
/// the moment they are created; yielding repeatedly is what turns "the scheduler
/// happened not to get to it" into a result that reproduces.
private func settle() async {
    for _ in 0..<20 {
        await Task.yield()
    }
}

/// Records what the handler received, and lets a test wait for a given number of
/// deliveries.
///
/// The wait replaces the drain seam the previous mechanism needed on the
/// production type: the handler belongs to the test, so the test can observe
/// delivery directly instead of the relay having to expose its progress.
private actor Recorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }

    /// Returns once at least `count` values have been recorded.
    ///
    /// Polls instead of parking on a continuation so that a regression fails
    /// rather than hangs. A `CheckedContinuation` nobody resumes also ignores
    /// cancellation, so `.timeLimit` cannot end the test — an implementation
    /// that never delivers would wedge the run instead of reporting.
    func wait(untilCount count: Int) async {
        while entries.count < count, !Task.isCancelled {
            await Task.yield()
        }
    }
}

/// A one-shot signal: `wait()` returns once `signal()` has been called, whether
/// that happened before or after the wait began.
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
