//
//  WaitUntil.swift
//  CoreTesting
//
//  The canonical async polling helper for tests outside Playback (#766).
//  Replaces three divergent local copies — the near-identical clock-plus-sleep
//  private methods in `PlaylistServiceLiveUpdatesTests` and
//  `PlaylistServiceWiringTests`, and a `PlaycutHistoryStoreTests` hard-coded
//  250x20ms loop that silently returned on timeout instead of failing.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Polls `condition` until it returns `true` or `timeout` elapses.
///
/// Callers MUST assert on the returned `Bool` — discarding a `false` result
/// turns a real timeout back into a swallowed flake, which is the defect this
/// helper exists to retire.
///
/// Playback keeps its own `PlaybackTestUtilities.pollUntil` rather than
/// adopting this: it takes a synchronous `@MainActor` predicate and returns
/// `Void`, shapes this signature can't serve, and its 30s
/// `stallTolerantTimeout` is derived from a measured CI stall. The polling
/// mechanic here is deliberately identical to it, so the two differ only in
/// isolation and return shape — never in timeout behavior.
///
/// Sleeps a millisecond between polls rather than spinning on `Task.yield()`.
/// That is the same mechanic `PlaybackTestUtilities.pollUntil` settled on in
/// #807, for the same two reasons, and this helper deliberately matches it:
///
/// 1. Most of what these waits await is work on the very actor the condition
///    reads — an ingest task draining into a store, a reconnect loop bumping a
///    counter. A yield spin competes with that work over exactly the resource
///    it needs to progress; a sleep suspends and lets it run.
/// 2. `Task.yield()` neither throws on cancellation nor checks
///    `Task.isCancelled`, so a spin cannot be cut short by Swift Testing's
///    `.timeLimit` — an unmet condition pins a cooperative thread for the whole
///    budget instead of failing. `Task.sleep` is a cancellation point, so the
///    time limit stays real.
///
/// Timing is measured with `ContinuousClock`, which — unlike a wall-clock
/// `Date` comparison — doesn't drift when the system clock changes mid-test.
///
/// `condition` is `sending`: callers can pass a closure capturing
/// non-`Sendable` local state, since this function is nonisolated and the
/// closure crosses into it exactly once.
///
/// - Parameters:
///   - timeout: The maximum time to wait. One second suits conditions that
///     resolve as soon as the executor drains. It is *not* sized for a loaded
///     CI machine — #807 measured the test process being descheduled for
///     ~10.5s at a stretch — so a wait that has to survive that should pass an
///     explicit timeout, as the `PlaycutHistoryStore` ingest waits do.
///   - condition: An async predicate, re-evaluated on every poll.
/// - Returns: `true` if `condition` became true before the deadline, `false`
///   on timeout or cancellation. Callers must assert on the result (e.g.
///   `#expect(...)`) — a discarded `false` silently converts a real failure
///   into a pass.
public func waitUntil(
    timeout: Duration = .seconds(1),
    _ condition: sending () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() {
            return true
        }
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            // Cancelled — report the condition as it stands rather than
            // spinning out the remaining deadline. Swallowing this with `try?`
            // would rebuild the uncancellable spin the sleep exists to avoid.
            return await condition()
        }
    }
    return await condition()
}
