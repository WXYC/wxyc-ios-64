//
//  SerialHandoff.swift
//  Core
//
//  Delivers async work from a synchronous MainActor caller to its destination
//  actor in the order it was enqueued. Lives in Core, alongside the other
//  dependency-free concurrency utilities, so any package can reach it — the
//  same chain is currently open-coded in Playlist's `PlaycutHistoryStore`.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Serializes async work handed off from a synchronous `@MainActor` context.
///
/// A bare `Task { await destination.apply(x) }` per call is the obvious way to
/// bridge a synchronous callback into an actor, and it is wrong whenever the
/// order of the calls carries meaning. Unstructured tasks have no relative
/// ordering guarantee: two created back to back may reach the destination in
/// either order, so the *last* call does not reliably produce the *final*
/// state.
///
/// That is not theoretical here. Scene-phase changes and the per-window
/// `.onAppear` both push foreground state at `PlaylistService`, and an inverted
/// `.background`/`.active` pair latched `isForegrounded = false` while the app
/// was on screen. Nothing re-checks that flag once set, so the `live-fs-topic`
/// SSE subscription stayed down for the remainder of the session and the
/// playlist fell back to its 300 s reconciliation poll — the app visibly
/// trailing the flowsheet.
///
/// Each enqueued item awaits its predecessor, so arrival order is preserved and
/// the value enqueued last is the value that lands last. This mirrors the chain
/// already used by `PlaycutHistoryStore.ingest(_:)`.
///
/// Ordering is preserved; concurrency is given up. Items run one at a time, so
/// this is for short handoffs, not for work that should overlap.
@MainActor
public final class SerialHandoff {
    /// The most recently enqueued item; `nil` until the first `enqueue`.
    ///
    /// Only ever read and written on the MainActor, so the chain cannot be
    /// spliced concurrently and no additional synchronization is needed.
    private var tail: Task<Void, Never>?

    public init() {}

    /// Enqueues work to run after everything already enqueued has finished.
    ///
    /// Returns immediately — this is the bridge out of a synchronous caller.
    ///
    /// - Parameter work: The work to run. Runs exactly once, after all
    ///   previously enqueued work completes.
    public func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = tail
        tail = Task {
            // Awaiting a `Task<Void, Never>` cannot throw or fail, so a slow
            // predecessor delays the chain but can never break it.
            await previous?.value
            await work()
        }
    }

    /// Waits for all work enqueued so far to finish.
    ///
    /// Work enqueued *after* this call is not awaited — the chain's tail is
    /// captured when `drain()` is entered.
    ///
    /// A testing seam, and currently only that: every production caller
    /// enqueues and moves on, which is the point of the type. It does not
    /// clear `tail`, so the last task stays retained after draining.
    public func drain() async {
        await tail?.value
    }
}
