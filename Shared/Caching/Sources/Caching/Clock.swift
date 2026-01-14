//
//  Clock.swift
//  Caching
//
//  Time abstraction for testable TTL-based cache expiration.
//
//  Created by Jake Bromberg on 01/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - Clock Protocol

/// Protocol for providing the current time, enabling testable time-dependent code.
///
/// By abstracting time behind a protocol, code that depends on the current time
/// can be tested deterministically. In production, use ``SystemClock``. In tests,
/// inject a mock clock that returns controlled values.
///
/// ## Example
///
/// ```swift
/// // Production: uses real system time
/// let coordinator = CacheCoordinator(cache: cache, clock: SystemClock())
///
/// // Testing: uses controlled time
/// struct MockClock: Clock {
///     var now: TimeInterval = 0
/// }
/// var mockClock = MockClock()
/// let testCoordinator = CacheCoordinator(cache: cache, clock: mockClock)
///
/// // Fast-forward time to test expiration
/// mockClock.now += 86400 // Advance 24 hours
/// ```
public protocol Clock: Sendable {
    /// The current time as seconds since the reference date (January 1, 2001).
    ///
    /// This value is compatible with `Date.timeIntervalSinceReferenceDate`.
    var now: TimeInterval { get }
}

// MARK: - SystemClock

/// Default clock implementation that uses the system time.
///
/// This is the clock used in production code. It returns the actual
/// current time from the system.
public struct SystemClock: Clock, Sendable {
    /// Creates a system clock instance.
    public init() {}

    /// The current system time as seconds since the reference date.
    public var now: TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }
}
