//
//  WaitUntil.swift
//  CoreTesting
//
//  The canonical async polling helper for tests (#766). Replaces four
//  divergent local copies — two `ContinuousClock`/`Date`-based methods on the
//  Playback test harnesses, a `PlaylistServiceLiveUpdatesTests` clock-plus-sleep
//  private method, and a `PlaycutHistoryStoreTests` hard-coded 250x20ms loop
//  that silently returned on timeout instead of failing. Callers MUST assert
//  on the returned `Bool` — discarding a `false` result turns a real timeout
//  back into a swallowed flake.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Polls `condition` until it returns `true` or `timeout` elapses.
///
/// Backs off with `Task.yield()` between polls rather than a fixed sleep, so
/// the loop drains as fast as the cooperative executor allows instead of
/// waiting out a fixed interval. Timing is measured with `ContinuousClock`,
/// which — unlike a wall-clock `Date` comparison — doesn't drift when the
/// system clock changes mid-test.
///
/// `condition` is `sending`: callers on `@MainActor` types can pass a closure
/// that captures actor-isolated state (e.g. `{ self.player.state == .playing }`
/// inside a `@MainActor` harness) without a Sendable conformance, since this
/// function is nonisolated and the closure crosses into it exactly once.
///
/// - Parameters:
///   - timeout: The maximum time to wait. Defaults to one second.
///   - condition: An async predicate, re-evaluated on every poll.
/// - Returns: `true` if `condition` became true before the deadline, `false`
///   on timeout. Callers must assert on the result (e.g. `#expect(...)`) —
///   a discarded `false` silently converts a real failure into a pass.
public func waitUntil(
    timeout: Duration = .seconds(1),
    _ condition: sending () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}
