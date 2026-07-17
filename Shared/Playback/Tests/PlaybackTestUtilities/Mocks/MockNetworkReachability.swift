//
//  MockNetworkReachability.swift
//  Playback
//
//  Mock implementation of NetworkReachability for testing. Lets tests drive
//  `.satisfied`/`.unsatisfied` path transitions deterministically without a
//  live network. See WXYC/wxyc-ios-64#517.
//
//  Created by Jake Bromberg on 07/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PlaybackCore

/// A test double for `NetworkReachability`. Subscribers receive the current
/// path state immediately on subscription, then every value pushed via
/// `send(satisfied:)`. Multiple concurrent subscriptions are supported (each
/// `pathUpdates()` call gets its own stream), so a consumer that re-enters its
/// reconnect phase and re-subscribes still observes updates.
public final class MockNetworkReachability: NetworkReachability, @unchecked Sendable {

    private let lock = NSLock()
    private var current: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    /// - Parameter initialSatisfied: the path state delivered to each new
    ///   subscriber on subscription. Defaults to `true` (a healthy network).
    public init(initialSatisfied: Bool = true) {
        self.current = initialSatisfied
    }

    public func pathUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
                // Deliver the current state immediately so a consumer can gate
                // without waiting for the next transition, mirroring
                // NWPathMonitor's prompt-on-start behaviour.
                continuation.yield(current)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
            }
        }
    }

    // MARK: - Test Control

    /// Pushes a new path state to all active subscribers. A value equal to the
    /// current one is still delivered (subscribers dedupe edges themselves), so
    /// tests can assert redundant satisfied→satisfied transitions are ignored.
    public func send(satisfied: Bool) {
        lock.withLock {
            current = satisfied
            for continuation in continuations.values {
                continuation.yield(satisfied)
            }
        }
    }

    /// Finishes all active streams (models the monitor being torn down).
    /// Snapshots and clears the continuations *under* the lock, then finishes
    /// them *outside* it: `Continuation.finish()` invokes `onTermination`
    /// synchronously, and that handler re-acquires the same (non-recursive)
    /// `NSLock`, so finishing while holding the lock would deadlock.
    public func finish() {
        let active = lock.withLock { () -> [AsyncStream<Bool>.Continuation] in
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        for continuation in active {
            continuation.finish()
        }
    }
}
