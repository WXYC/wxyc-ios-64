//
//  StartupWatchdogGate.swift
//  Playback
//
//  Deterministic stand-in for the wall-clock sleep behind a startup watchdog's
//  deadline (`MP3Streamer.armStartupWatchdog()` and
//  `AudioPlayerController.armStartupWatchdog()`). A real watchdog races
//  scheduler latency: under parallel-simulator load, the deadline can expire
//  before an async signal the watchdog depends on (e.g. `isWaitingForConnectivity`)
//  has had a chance to propagate, manufacturing the very escalation the test is
//  trying to prove does NOT happen. This gate removes the wall clock from the
//  decision entirely — a watchdog armed against it does not fire until the test
//  explicitly releases it, so a test can first prove a precondition (the park
//  signal landed) and only then let the watchdog fire, with no timing window in
//  which the two can race. See issue #787.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A one-shot-per-arm turnstile: each call to `sleep(for:)` suspends until the
/// next `release()`, mirroring how a watchdog's `Task.sleep` suspends until its
/// deadline elapses — except the "deadline" is now a test-driven event instead
/// of real elapsed time. Consumers re-arm by calling `sleep(for:)` again (a
/// watchdog that defers and re-arms itself needs one `release()` per arm).
///
/// `@MainActor` because both watchdogs this gates run their deadline task on
/// the main actor, and the test driving `release()` runs there too — no
/// locking needed.
@MainActor
public final class StartupWatchdogGate {
    private var pendingReleases: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Suspends until the next `release()`. The `duration` argument is
    /// accepted (to match the shape of `Task.sleep(for:)`) but ignored — this
    /// gate's whole point is that real elapsed time no longer decides when a
    /// watchdog fires.
    public func sleep(for duration: Duration) async throws {
        await withCheckedContinuation { continuation in
            pendingReleases.append(continuation)
        }
    }

    /// Whether an armed watchdog is currently suspended on this gate, waiting
    /// to be released. Lets a test wait for the watchdog to actually reach the
    /// gate (a logic-based wait, not a time-based one) before releasing it —
    /// releasing before the watchdog has armed would otherwise be a no-op.
    public var hasPendingArm: Bool { !pendingReleases.isEmpty }

    /// Blocks the caller (via cooperative yielding, not a wall-clock sleep)
    /// until a watchdog has armed against this gate. Safe to await for as long
    /// as it takes — nothing else is racing a deadline while this waits.
    public func waitForArm() async {
        while !hasPendingArm {
            await Task.yield()
        }
    }

    /// Resumes the oldest still-suspended `sleep(for:)` call, i.e. lets exactly
    /// one armed watchdog "fire". No-op if nothing is currently pending.
    public func release() {
        guard !pendingReleases.isEmpty else { return }
        let continuation = pendingReleases.removeFirst()
        continuation.resume()
    }

    /// Resumes every currently-suspended `sleep(for:)` call. Intended for test
    /// teardown: a watchdog's final re-arm is often left un-released on
    /// purpose (the test stopped driving it once its assertions were made), so
    /// without this a `CheckedContinuation` would stay suspended past the
    /// test's lifetime. Safe to call after the owning player/controller has
    /// already been stopped — the resumed watchdog task's own cancellation
    /// check discards the result.
    public func releaseAll() {
        let pending = pendingReleases
        pendingReleases.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
