//
//  MockLiveFsEventSource.swift
//  PlaylistTesting
//
//  Test double for LiveFsEventSource: yields a scripted list of LiveFsEvents on
//  each connect, optionally finishing the stream afterwards (to exercise the
//  consumer's reconnect path) or keeping it open (to model a live connection).
//  See WXYC/wxyc-ios-64#269.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Synchronization
@_exported import Playlist

/// Test double for ``LiveFsEventSource`` that replays a fixed script of events.
///
/// Pass the mock as `liveEventSource:` and the service wires it in
/// unconditionally — the caller's opt-in is now the only gate.
///
/// This used to carry a trap worth remembering: the service resolved a
/// `PlaylistAPIVersion` from the shared `UserDefaults.wxyc` app group, so a
/// debug override left on the simulator by an earlier run could pin a test to
/// `.v1`, which had no push channel. The service then wired in no source, this
/// mock was never connected, and the test passed while exercising nothing.
/// Removing the v1 path (#262) removed that failure mode by construction: there
/// is no version to resolve and no process-global lookup to be poisoned.
/// See WXYC/wxyc-ios-64#749.
///
/// ```swift
/// let source = MockLiveFsEventSource(events: [.insert(.stub(id: 42))])
/// let service = PlaylistService(fetcher: fetcher, interval: 300,
///                               cacheCoordinator: coordinator,
///                               liveEventSource: source)
/// await service.setForegrounded(true)
/// ```
public final class MockLiveFsEventSource: LiveFsEventSource, @unchecked Sendable {
    private let script: [LiveFsEvent]
    private let finishesAfterScript: Bool
    private let connects = Mutex(0)

    /// - Parameters:
    ///   - events: The events yielded, in order, on every ``connect()``.
    ///   - finishesAfterScript: When `true` the stream finishes once the script
    ///     is drained, so a reconnecting consumer calls ``connect()`` again;
    ///     when `false` (the default) the stream stays open, modelling a live
    ///     connection that ends only when the consumer cancels.
    public init(events: [LiveFsEvent] = [], finishesAfterScript: Bool = false) {
        self.script = events
        self.finishesAfterScript = finishesAfterScript
    }

    /// The number of times ``connect()`` has been called — one per connection
    /// attempt, so a value > 1 means the consumer reconnected.
    public var connectCount: Int {
        connects.withLock { $0 }
    }

    public func connect() -> AsyncStream<LiveFsEvent> {
        connects.withLock { $0 += 1 }
        let script = self.script
        let finishes = self.finishesAfterScript
        return AsyncStream { continuation in
            for event in script {
                continuation.yield(event)
            }
            if finishes {
                continuation.finish()
            }
            // Otherwise the stream stays open; AsyncStream finishes it when the
            // consuming task is cancelled (backgrounding), which is exactly the
            // teardown `PlaylistService.setForegrounded(false)` triggers.
        }
    }
}
