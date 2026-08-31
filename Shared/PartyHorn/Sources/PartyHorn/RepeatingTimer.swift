//
//  RepeatingTimer.swift
//  PartyHorn
//
//  Repeating timer utility for animation timing.
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// Fires `block` on the main actor every `interval`, after an initial delay.
///
/// The loop holds `block` rather than the timer, so a released timer would leave
/// its loop running forever — `deinit`'s cancellation is load-bearing, not
/// defensive. Callers must still capture weakly in `block` itself: a timer stored
/// on the same object the block reaches back into is a reference cycle, and
/// nothing here can break it from the inside.
@MainActor
final class RepeatingTimer {
    private let initialDelay: Duration
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let block: @MainActor () -> Void
    private var task: Task<Void, Never>?

    /// Whether a tick loop is currently running.
    var isRunning: Bool { task != nil }

    /// - Parameters:
    ///   - initialDelay: How long to wait before the first tick.
    ///   - interval: The gap between subsequent ticks.
    ///   - sleep: The suspension used between ticks. Injected so tests can drive
    ///     the schedule without waiting in real time.
    ///   - block: Run on each tick.
    init(
        initialDelay: Duration,
        interval: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        block: @escaping @MainActor () -> Void
    ) {
        self.initialDelay = initialDelay
        self.interval = interval
        self.sleep = sleep
        self.block = block
    }

    /// Starts ticking. Does nothing if a loop is already running, so a repeated
    /// `start()` cannot stack a second loop onto the same timer.
    func start() {
        guard task == nil else { return }

        task = Task { [initialDelay, interval, sleep, block] in
            do {
                try await sleep(initialDelay)

                while !Task.isCancelled {
                    block()
                    try await sleep(interval)
                }
            } catch {
                // Cancelled mid-sleep; nothing to unwind.
            }
        }
    }

    /// Stops ticking. Safe to call when not running.
    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
