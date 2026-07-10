//
//  MockClock.swift
//  CachingTesting
//
//  Controllable Clock implementation for deterministic testing of TTL-based
//  expiration without sleeps. Shared by CachingTests and downstream packages
//  that test against an injected CacheCoordinator clock.
//
//  Created by Jake Bromberg on 07/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Foundation

/// A controllable clock for testing time-dependent behavior without sleeps.
///
/// Inject into `CacheCoordinator` (and other `Clock` consumers) to make TTL
/// expiration deterministic:
///
/// ```swift
/// let clock = MockClock()
/// let coordinator = CacheCoordinator(cache: InMemoryCache(), clock: clock)
/// clock.advance(by: 91 * 24 * 60 * 60) // fast-forward past a 90-day lifespan
/// ```
public final class MockClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: TimeInterval

    /// Creates a mock clock.
    ///
    /// - Parameter now: The initial time, as seconds since the reference date.
    public init(now: TimeInterval = 1_000_000) {
        self._now = now
    }

    /// The current mock time, as seconds since the reference date.
    public var now: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    /// Advances the mock time by the given interval.
    public func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        _now += interval
    }
}
