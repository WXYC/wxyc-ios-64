//
//  PlaybackHeartbeat.swift
//  PlaybackCore
//
//  Owns the periodic `playback_heartbeat` cadence (#666): cancel-then-
//  loop-sleep-emit. Extracted from AudioPlayerController and
//  RadioPlayerController, whose `startHeartbeat`/`stopHeartbeat` bodies were
//  byte-identical, so both controllers now compose this single
//  implementation instead of maintaining their own copies (#755).
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Owns the cancel-then-loop-sleep-emit task shape for a periodic cadence.
/// Callers supply the interval and an `onTick` callback — typically closing
/// over `self` weakly — invoked once per tick while the heartbeat is running.
///
/// Idempotent by construction: `start()` cancels any prior loop first, so a
/// redundant call collapses to a single live timer rather than stacking
/// overlapping loops.
@MainActor
public final class PlaybackHeartbeat {
    private let interval: Duration
    private let onTick: () -> Void
    private var task: Task<Void, Never>?
    /// The sleep behind each tick's cadence. Defaults to the real `Task.sleep`,
    /// so production is untouched; tests substitute a gate so ticks are driven
    /// by an explicit signal instead of racing a wall-clock deadline against
    /// however long the test process actually gets scheduled — see
    /// `MP3Streamer.startupWatchdogSleep` (issue #787) for the seam this
    /// mirrors, and issue #807 for why this component needed the same one.
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameters:
    ///   - interval: Cadence between ticks.
    ///   - sleep: The sleep behind each tick's cadence. Defaults to the real
    ///     wall clock; tests inject a gate. Every call must throw only on
    ///     cancellation, exactly like `Task.sleep(for:)`. Ordered before
    ///     `onTick`, not after, so production call sites that pass `onTick`
    ///     as a trailing closure are unaffected by this parameter's addition.
    ///   - onTick: Invoked on the main actor once per elapsed interval while running.
    public init(
        interval: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onTick: @escaping () -> Void
    ) {
        self.interval = interval
        self.onTick = onTick
        self.sleep = sleep
    }

    /// Cancels a running loop when the heartbeat is released without an
    /// explicit `stop()`.
    ///
    /// Load-bearing, not defensive. The controller-owned loops this replaces
    /// captured their owner weakly and ended themselves on `guard ... let
    /// self else { return }`; this loop captures `interval` and `onTick` by
    /// value and never mentions `self`, so it has no equivalent exit. Without
    /// this `deinit` a released heartbeat would wake the main actor every
    /// interval for the life of the process.
    @MainActor
    deinit {
        task?.cancel()
    }

    /// Starts (or restarts) the periodic cadence.
    ///
    /// Only `interval` and `onTick` are captured by value across the sleep —
    /// not `self` — so a live loop never extends this instance's lifetime.
    /// Termination on release is `deinit`'s job, since the loop itself has no
    /// reference to the owner to notice it going away.
    public func start() {
        task?.cancel()
        task = Task { [interval, onTick, sleep] in
            while true {
                do {
                    try await sleep(interval)
                } catch {
                    // Cancelled mid-sleep.
                    return
                }
                guard !Task.isCancelled else { return }
                onTick()
            }
        }
    }

    /// Stops the cadence and cancels its task. Idempotent — safe to call
    /// whether or not a heartbeat is currently running.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
