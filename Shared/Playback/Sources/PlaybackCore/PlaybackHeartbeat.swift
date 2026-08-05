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

    /// - Parameters:
    ///   - interval: Cadence between ticks.
    ///   - onTick: Invoked on the main actor once per elapsed interval while running.
    public init(interval: Duration, onTick: @escaping () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    /// Starts (or restarts) the periodic cadence.
    ///
    /// Only `interval` and `onTick` are captured by value across the sleep —
    /// not `self` — so a live loop never extends this instance's lifetime,
    /// matching the original controller-owned implementations this replaces.
    public func start() {
        task?.cancel()
        task = Task { [interval, onTick] in
            while true {
                do {
                    try await Task.sleep(for: interval)
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
