//
//  SingletoniaForegroundRoutingTests.swift
//  WXYC
//
//  Drives `Singletonia.ForegroundRouter` — the real code path between a scene
//  phase and its three consumers — with recorder sinks. The first two
//  deliberately disagree about `.inactive`: widget reloads are budgeted and
//  only pay off while the app is frontmost, so they stop, while the live-fs
//  subscription must survive it (see `ForegroundVisibility` for that story).
//  Collapsing the two back into a single `Bool` is a regression in whichever
//  direction it collapses, and delivering to the playlist sink with a bare
//  `Task {}` per phase instead of the coalescing relay is the ordering
//  regression #835 fixed — both fail here.
//
//  The third consumer feeds the foreground-session measurement, and is pinned
//  here only as far as the router's own job goes: every phase's classification
//  reaches it, `.noChange` included. What that measurement then does with a run
//  of them — a Control Center pull is inside a visit, not the end of one —
//  belongs to `ForegroundSessionTrackerTests` and `ForegroundSessionReporterTests`.
//
//  What stays outside this pin is the one-line delegation in
//  `setScenePhase(_:)` and the `init` wiring of the real sinks.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import SwiftUI
import Testing
@testable import WXYC

/// Extracted to a top-level constant so the tuple array doesn't lean on the
/// type-checker inside the macro expansion. `nonisolated` because the `@Test`
/// macro reads the arguments outside the suite's main-actor isolation.
private nonisolated let routingRows: [(ScenePhase, [Bool], [Bool])] = [
    (.active, [true], [true]),
    (.background, [false], [false]),
    // The row the two consumers disagree on: widgets stop, and nothing at all
    // reaches the subscription.
    (.inactive, [false], []),
]

@MainActor
@Suite("Singletonia foreground routing")
struct SingletoniaForegroundRoutingTests {

    @Test(
        "Each phase routes to both consumers under their own rule",
        .timeLimit(.minutes(1)),
        arguments: routingRows
    )
    func phaseRoutesToBothConsumers(
        phase: ScenePhase,
        expectedWidgets: [Bool],
        expectedPlaylist: [Bool]
    ) async {
        let widgets = Recorder<Bool>()
        let playlist = PlaylistRecorder()
        let router = makeRouter(
            setWidgetsForegrounded: { widgets.record($0) },
            setPlaylistForegrounded: { await playlist.record($0) }
        )

        router.route(entering: phase)

        // The widget sink is called synchronously, so a wrong value is visible
        // immediately; the playlist sink is async, so give anything wrongly
        // dispatched a generous chance to land before asserting it didn't.
        #expect(widgets.values == expectedWidgets)

        await playlist.wait(untilCount: expectedPlaylist.count)
        await settle()
        #expect(await playlist.values == expectedPlaylist)
    }

    @Test(
        "A transient interruption passes through without touching the subscription",
        .timeLimit(.minutes(1))
    )
    func inactiveSendsNothingWithinASequence() async {
        let widgets = Recorder<Bool>()
        let playlist = PlaylistRecorder()
        let router = makeRouter(
            setWidgetsForegrounded: { widgets.record($0) },
            setPlaylistForegrounded: { await playlist.record($0) }
        )

        // Waiting out each delivery before routing the next phase keeps the
        // relay's coalescing from absorbing a wrong `.inactive` send — anything
        // sent here has to show up in the final array.
        router.route(entering: .active)
        await playlist.wait(untilCount: 1)

        router.route(entering: .inactive)
        await settle()

        router.route(entering: .background)
        await playlist.wait(untilCount: 2)
        await settle()

        #expect(widgets.values == [true, false, false])
        #expect(await playlist.values == [true, false])
    }

    @Test(
        "A phase burst reaches the subscription coalesced, not one task per phase",
        .timeLimit(.minutes(1))
    )
    func burstReachesSubscriptionThroughTheRelay() async {
        let playlist = PlaylistRecorder()
        let gate = Gate()

        let router = makeRouter(
            setPlaylistForegrounded: { value in
                await playlist.record(value)
                if await playlist.values.count == 1 {
                    await gate.waitUntilOpen()
                }
            }
        )

        // Park the handler on the first delivery, then pile up a burst the way
        // a rapid `.background`/`.active` pair arrives.
        router.route(entering: .background)
        await playlist.wait(untilCount: 1)

        router.route(entering: .active)
        router.route(entering: .background)
        router.route(entering: .active)

        await gate.open()
        await playlist.wait(untilCount: 2)
        await settle()

        // Exactly two deliveries: the parked first and the coalesced newest. A
        // bare `Task {}` per phase — the regression this wiring exists to
        // prevent — delivers all four.
        #expect(await playlist.values == [false, true])
    }

    // MARK: - Foreground session measurement

    @Test(
        "Every phase forwards its classification, including the inert one",
        arguments: [
            (ScenePhase.active, ForegroundVisibility.onScreen),
            (ScenePhase.background, ForegroundVisibility.offScreen),
            // Forwarded rather than filtered here: whether `.noChange` leaves
            // a visit running is `ForegroundSessionReporter`'s rule, and a
            // router that swallowed it would be applying that rule twice, in
            // two places, with only one of them under test.
            (ScenePhase.inactive, ForegroundVisibility.noChange),
        ]
    )
    func phaseForwardsItsVisibility(phase: ScenePhase, expected: ForegroundVisibility) {
        let visibilities = Recorder<ForegroundVisibility>()
        let router = makeRouter(recordForegroundVisibility: { visibilities.record($0) })

        router.route(entering: phase)

        // `.active` is also what the initial (`initial: true`) delivery looks
        // like from here — the router cannot tell a launch from a return, and
        // must not, or a launch-into-active visit would go unmeasured.
        #expect(visibilities.values == [expected])
    }

    /// Builds a router with every sink inert unless a test asks for one, so a
    /// fourth consumer costs this file one defaulted parameter instead of an
    /// edit at every construction site.
    private func makeRouter(
        setWidgetsForegrounded: @escaping (Bool) -> Void = { _ in },
        setPlaylistForegrounded: @escaping @Sendable (Bool) async -> Void = { _ in },
        recordForegroundVisibility: @escaping (ForegroundVisibility) -> Void = { _ in }
    ) -> Singletonia.ForegroundRouter {
        Singletonia.ForegroundRouter(
            setWidgetsForegrounded: setWidgetsForegrounded,
            setPlaylistForegrounded: setPlaylistForegrounded,
            recordForegroundVisibility: recordForegroundVisibility
        )
    }
}

// MARK: - Test helpers

/// Records what the router pushed at a synchronous sink. The widget and
/// session sinks are both called inline on the main actor, so no waiting is
/// involved — `PlaylistRecorder` below is an actor because its sink is async.
@MainActor
private final class Recorder<Value> {
    private(set) var values: [Value] = []

    func record(_ value: Value) {
        values.append(value)
    }
}

/// Records what reached the playlist sink, and lets a test wait for a given
/// number of deliveries. Mirrors `LatestValueRelayTests`' recorder: polls
/// instead of parking on a continuation so a regression fails inside the time
/// limit rather than wedging the run.
private actor PlaylistRecorder {
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        values.append(value)
    }

    /// Returns once at least `count` values have been recorded.
    func wait(untilCount count: Int) async {
        while values.count < count, !Task.isCancelled {
            await Task.yield()
        }
    }
}

/// Holds the playlist handler open until the test releases it. Polls for the
/// same reason `PlaylistRecorder.wait(untilCount:)` does.
private actor Gate {
    private var isOpen = false

    func open() {
        isOpen = true
    }

    func waitUntilOpen() async {
        while !isOpen, !Task.isCancelled {
            await Task.yield()
        }
    }
}

/// Gives any task that is already runnable a generous chance to run before the
/// caller asserts that it didn't — the negative assertions here are claims
/// about work that must *not* have happened, which no amount of awaiting can
/// establish outright.
private func settle() async {
    for _ in 0..<20 {
        await Task.yield()
    }
}
