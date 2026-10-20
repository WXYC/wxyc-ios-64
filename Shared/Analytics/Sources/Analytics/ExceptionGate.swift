//
//  ExceptionGate.swift
//  Analytics
//
//  Caps how many handled-error `$exception` events one app launch sends.
//
//  Created by Jake Bromberg on 10/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger
import Synchronization

/// Decides whether a handled error may be sent to PostHog as `$exception`.
///
/// PostHog's free plan stops accepting exceptions at 100K a month, org-wide, and the listener
/// app has the largest install base of any WXYC surface, so one device in a retry loop could
/// exhaust the cap for every surface. This is the client form of the server contract in
/// wiki `patterns/error-tracking.md` §5. Two gates run in order:
///
/// 1. **Dedupe, 60 seconds.** A key admitted less than 60 seconds ago is dropped. This runs
///    first, so a suppressed repeat costs no token. The table holds at most 1,000 keys.
/// 2. **Token bucket.** Burst 20, one token back every 30 minutes (a steady-state ceiling of
///    48 a day). Twenty is room for the distinct failures of a bad launch; 30 minutes keeps a
///    stuck device at 48 a day, so the fleet's exceptions stay a small share of the cap. The
///    bucket lives in memory and starts full at each launch.
///
/// Only the handled path (`StructuredPostHogAnalytics.captureException`) consults a gate.
/// MetricKit crash and hang diagnostics and PostHog's crash autocapture never do.
///
/// Time comes from an injected monotonic clock so tests can advance it by hand. Drops are
/// counted and logged as a warning at most once a minute; they are never sent.
public final class ExceptionGate: Sendable {
    static let dedupeWindow: Duration = .seconds(60)
    static let dedupeCapacity = 1_000
    static let refillInterval: Duration = .seconds(30 * 60)
    static let logInterval: Duration = .seconds(60)

    private struct State {
        var recent: [String: Duration] = [:]
        var tokens: Double
        var lastRefill: Duration
        var dropped = 0
        var droppedSinceLog = 0
        var lastLog: Duration?
    }

    private let burst: Double
    private let now: @Sendable () -> Duration
    private let state: Mutex<State>

    /// - Parameters:
    ///   - burst: The bucket's capacity, and the number of tokens it starts with.
    ///   - now: A monotonic clock, as the time elapsed since any fixed origin.
    public init(burst: Int = 20, now: @escaping @Sendable () -> Duration) {
        self.burst = Double(burst)
        self.now = now
        self.state = Mutex(State(tokens: Double(burst), lastRefill: now()))
    }

    /// A gate on the system's continuous clock, for production use.
    public convenience init() {
        let origin = ContinuousClock.now
        self.init(now: { origin.duration(to: .now) })
    }

    /// Total events refused since launch.
    var droppedCount: Int {
        state.withLock { $0.dropped }
    }

    var dedupeKeyCount: Int {
        state.withLock { $0.recent.count }
    }

    /// Returns whether an event with this dedupe key may be sent, spending a token if so.
    public func admit(key: String) -> Bool {
        let time = now()
        let (admitted, warning) = state.withLock { state -> (Bool, String?) in
            let elapsed = time - state.lastRefill
            state.tokens = min(burst, state.tokens + elapsed / Self.refillInterval)
            state.lastRefill = time

            if let admittedAt = state.recent[key], time - admittedAt < Self.dedupeWindow {
                return (false, Self.recordDrop(in: &state, at: time))
            }
            guard state.tokens >= 1 else {
                return (false, Self.recordDrop(in: &state, at: time))
            }
            state.tokens -= 1

            if state.recent.count >= Self.dedupeCapacity {
                state.recent = state.recent.filter { time - $0.value < Self.dedupeWindow }
            }
            if state.recent.count >= Self.dedupeCapacity,
               let oldest = state.recent.min(by: { $0.value < $1.value })?.key {
                state.recent[oldest] = nil
            }
            state.recent[key] = time
            return (true, nil)
        }
        if let warning {
            Log(.warning, category: .general, warning)
        }
        return admitted
    }

    /// Counts a drop and returns the warning to log, if one is due.
    private static func recordDrop(in state: inout State, at time: Duration) -> String? {
        state.dropped += 1
        state.droppedSinceLog += 1
        if let lastLog = state.lastLog, time - lastLog < logInterval {
            return nil
        }
        let message = "Dropped \(state.droppedSinceLog) handled-error $exception event(s) over the dedupe or rate limit (\(state.dropped) since launch)"
        state.lastLog = time
        state.droppedSinceLog = 0
        return message
    }
}
