//
//  NetworkReachability.swift
//  Playback
//
//  Injectable network-reachability signal used to gate and accelerate stream
//  reconnection, replacing a blind timed retry loop. See WXYC/wxyc-ios-64#517.
//
//  Created by Jake Bromberg on 07/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Network

/// An injectable network-reachability signal.
///
/// Vends a stream of path-satisfied updates so the reconnect machinery can idle
/// while the network is genuinely down — instead of waking on a timer,
/// re-activating the audio session, and attempting a connect that cannot
/// succeed — and resume promptly the moment connectivity returns.
///
/// The signal is *a gate and an accelerator, not a guarantee*: a `.satisfied`
/// path does not mean the stream host is reachable (captive portals, DNS
/// failures, an origin that is down all report `.satisfied`). The timed
/// reconnect fallback therefore remains for the "path satisfied but the connect
/// still fails" case; reachability only removes wasted work on a provably dead
/// network and shortens recovery on a network-return edge.
///
/// The concrete `NWPathMonitorReachability` is a thin passthrough over
/// `Network.framework` and is untestable by construction — a unit test cannot
/// drive a real network path — so all gating logic lives in the consumer behind
/// this seam, and tests inject a mock that yields `.satisfied`/`.unsatisfied`
/// deterministically.
public protocol NetworkReachability: Sendable {
    /// A stream of path-satisfied updates: `true` when a network route is
    /// available (`NWPath.Status.satisfied`), `false` otherwise.
    ///
    /// Monitoring begins when the stream is first iterated and stops when the
    /// stream terminates (i.e. the iterating task is cancelled). This gives a
    /// *pending-scoped* lifecycle: the consumer subscribes only while a
    /// reconnect is pending and tears the monitor down on recovery/stop, so
    /// there is no always-on cost while playback is healthy.
    ///
    /// Implementations should deliver the current path status promptly on
    /// subscription so a consumer can gate on it without waiting for the next
    /// transition.
    func pathUpdates() -> AsyncStream<Bool>
}

/// `NWPathMonitor`-backed reachability. A deliberately thin passthrough: it owns
/// no gating logic (that lives in the consumer, behind `NetworkReachability`, so
/// it is unit-testable) and simply maps `NWPath.status == .satisfied` to a
/// `Bool` stream.
///
/// A fresh `NWPathMonitor` is created per `pathUpdates()` call and cancelled
/// when the returned stream terminates, matching the pending-scoped lifecycle
/// described on the protocol.
public final class NWPathMonitorReachability: NetworkReachability {
    public init() {}

    public func pathUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            // `NWPathMonitor` mandates a `DispatchQueue` for its update callback;
            // this is a framework requirement, not app-level GCD concurrency.
            // The queue is confined to this thin adapter and never used to
            // schedule our own work.
            let queue = DispatchQueue(label: "org.wxyc.playback.reachability")
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }
}
